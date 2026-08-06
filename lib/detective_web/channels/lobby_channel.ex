defmodule DetectiveWeb.LobbyChannel do
  use DetectiveWeb, :channel

  alias Detective.Games
  alias Detective.Games.LobbyBroadcaster
  alias Detective.Invitations
  alias Detective.Security.RateLimiter
  alias DetectiveWeb.Presence

  @command_limit 10
  @rate_window_ms 2_000

  @impl true
  def join("lobby:" <> game_id, _payload, socket) do
    case Games.get_lobby(socket.assigns.current_scope, game_id) do
      {:ok, lobby} ->
        socket =
          socket
          |> assign(:game_id, lobby.id)
          |> assign(:player_id, lobby.membership.id)

        send(self(), :after_join)
        {:ok, %{lobby: lobby}, socket}

      {:error, reason} ->
        {:error, %{code: error_code(reason)}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _presence_ref} =
      Presence.track(socket, socket.assigns.player_id, %{
        online_at: System.system_time(:second)
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in("ready", %{"expected_version" => expected_version}, socket) do
    with_rate_limit(socket, fn -> update_ready(socket, expected_version, true) end)
  end

  def handle_in("unready", %{"expected_version" => expected_version}, socket) do
    with_rate_limit(socket, fn -> update_ready(socket, expected_version, false) end)
  end

  def handle_in(
        "start_game",
        %{"command_id" => command_id, "expected_version" => expected_version},
        socket
      ) do
    with_rate_limit(socket, fn ->
      case Games.start_game(
             socket.assigns.current_scope,
             socket.assigns.game_id,
             command_id,
             expected_version
           ) do
        {:ok, %{lobby: lobby}} ->
          {:reply,
           {:ok,
            %{
              path: "/games/#{lobby.id}",
              version: lobby.current_version
            }}, socket}

        {:error, reason} ->
          {:reply, {:error, %{code: error_code(reason)}}, socket}
      end
    end)
  end

  def handle_in("leave_lobby", %{"expected_version" => expected_version}, socket) do
    with_rate_limit(socket, fn ->
      case Games.leave_lobby(
             socket.assigns.current_scope,
             socket.assigns.game_id,
             expected_version
           ) do
        {:ok, %{event: event, player_id: player_id, lobby: lobby}} ->
          :ok = LobbyBroadcaster.broadcast_lobby(lobby)
          :ok = LobbyBroadcaster.broadcast_player_departure(lobby, event, player_id)

          {:reply, {:ok, %{path: "/dashboard", version: lobby.current_version}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{code: error_code(reason)}}, socket}
      end
    end)
  end

  def handle_in(
        "remove_player",
        %{"player_id" => player_id, "expected_version" => expected_version},
        socket
      ) do
    with_rate_limit(socket, fn ->
      case Games.remove_player(
             socket.assigns.current_scope,
             socket.assigns.game_id,
             player_id,
             expected_version
           ) do
        {:ok, %{event: event, player_id: removed_player_id, lobby: lobby}} ->
          :ok = LobbyBroadcaster.broadcast_lobby(lobby)

          :ok =
            LobbyBroadcaster.broadcast_player_departure(lobby, event, removed_player_id)

          {:reply, {:ok, %{version: lobby.current_version}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{code: error_code(reason)}}, socket}
      end
    end)
  end

  def handle_in("revoke_invite", %{"expected_version" => expected_version}, socket) do
    with_rate_limit(socket, fn ->
      case Invitations.revoke(
             socket.assigns.current_scope,
             socket.assigns.game_id,
             expected_version
           ) do
        {:ok, _result} ->
          broadcast_updated_lobby(socket)

        {:error, reason} ->
          {:reply, {:error, %{code: error_code(reason)}}, socket}
      end
    end)
  end

  def handle_in(
        "regenerate_invite",
        %{"expected_version" => expected_version, "invite_hours" => invite_hours},
        socket
      ) do
    with_rate_limit(socket, fn ->
      case Invitations.regenerate(
             socket.assigns.current_scope,
             socket.assigns.game_id,
             expected_version,
             invite_hours
           ) do
        {:ok, %{token: token}} ->
          with {:ok, lobby} <-
                 Games.get_lobby(socket.assigns.current_scope, socket.assigns.game_id) do
            :ok = LobbyBroadcaster.broadcast_lobby(lobby)

            {:reply,
             {:ok,
              %{
                invite_path: "/invites/#{token}",
                version: lobby.current_version
              }}, socket}
          else
            {:error, reason} ->
              {:reply, {:error, %{code: error_code(reason)}}, socket}
          end

        {:error, reason} ->
          {:reply, {:error, %{code: error_code(reason)}}, socket}
      end
    end)
  end

  def handle_in(
        "update_lobby_settings",
        %{
          "case_version_id" => case_version_id,
          "max_detectives" => max_detectives,
          "expected_version" => expected_version
        },
        socket
      ) do
    with_rate_limit(socket, fn ->
      case Games.update_lobby_settings(
             socket.assigns.current_scope,
             socket.assigns.game_id,
             %{
               case_version_id: case_version_id,
               max_detectives: max_detectives
             },
             expected_version
           ) do
        {:ok, %{lobby: lobby}} ->
          :ok = LobbyBroadcaster.broadcast_lobby(lobby)
          {:reply, {:ok, %{version: lobby.current_version}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{code: error_code(reason)}}, socket}
      end
    end)
  end

  def handle_in("ready", _payload, socket), do: invalid_command(socket)
  def handle_in("unready", _payload, socket), do: invalid_command(socket)
  def handle_in("start_game", _payload, socket), do: invalid_command(socket)
  def handle_in("leave_lobby", _payload, socket), do: invalid_command(socket)
  def handle_in("remove_player", _payload, socket), do: invalid_command(socket)
  def handle_in("revoke_invite", _payload, socket), do: invalid_command(socket)
  def handle_in("regenerate_invite", _payload, socket), do: invalid_command(socket)
  def handle_in("update_lobby_settings", _payload, socket), do: invalid_command(socket)
  def handle_in(_event, _payload, socket), do: invalid_command(socket)

  defp update_ready(socket, expected_version, ready) do
    case Games.set_ready(
           socket.assigns.current_scope,
           socket.assigns.game_id,
           expected_version,
           ready
         ) do
      {:ok, %{lobby: lobby}} ->
        :ok = LobbyBroadcaster.broadcast_lobby(lobby)
        {:reply, {:ok, %{version: lobby.current_version}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{code: error_code(reason)}}, socket}
    end
  end

  defp broadcast_updated_lobby(socket) do
    case Games.get_lobby(socket.assigns.current_scope, socket.assigns.game_id) do
      {:ok, lobby} ->
        :ok = LobbyBroadcaster.broadcast_lobby(lobby)
        {:reply, {:ok, %{version: lobby.current_version}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{code: error_code(reason)}}, socket}
    end
  end

  defp invalid_command(socket),
    do:
      with_rate_limit(socket, fn ->
        {:reply, {:error, %{code: "invalid_command"}}, socket}
      end)

  defp with_rate_limit(socket, callback) do
    case RateLimiter.check(
           {:lobby_command, socket.assigns.user_id, socket.assigns.game_id},
           limit: @command_limit,
           window_ms: @rate_window_ms
         ) do
      :ok -> callback.()
      {:error, reason} -> {:reply, {:error, %{code: error_code(reason)}}, socket}
    end
  end

  defp error_code(reason)
       when reason in [
              :invalid_game_id,
              :not_a_member,
              :not_detective,
              :not_chisel,
              :game_not_found,
              :player_not_found,
              :game_not_waiting,
              :stale_version,
              :invalid_command,
              :invalid_invite_expiry,
              :invite_not_active,
              :invalid_lobby_settings,
              :capacity_below_membership,
              :case_version_not_published,
              :no_detectives,
              :not_enough_detectives,
              :too_many_detectives,
              :detectives_not_ready,
              :command_id_conflict,
              :duplicate_command,
              :invalid_initial_state,
              :rate_limited
            ],
       do: Atom.to_string(reason)

  defp error_code(_reason), do: "unavailable"
end
