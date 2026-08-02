defmodule DetectiveWeb.LobbyChannel do
  use DetectiveWeb, :channel

  alias Detective.Games
  alias Detective.Games.LobbyBroadcaster
  alias DetectiveWeb.Presence

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
    update_ready(socket, expected_version, true)
  end

  def handle_in("unready", %{"expected_version" => expected_version}, socket) do
    update_ready(socket, expected_version, false)
  end

  def handle_in("ready", _payload, socket), do: invalid_command(socket)
  def handle_in("unready", _payload, socket), do: invalid_command(socket)

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

  defp invalid_command(socket),
    do: {:reply, {:error, %{code: "invalid_command"}}, socket}

  defp error_code(reason)
       when reason in [
              :invalid_game_id,
              :not_a_member,
              :not_detective,
              :game_not_waiting,
              :stale_version,
              :invalid_command
            ],
       do: Atom.to_string(reason)

  defp error_code(_reason), do: "unavailable"
end
