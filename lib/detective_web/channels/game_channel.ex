defmodule DetectiveWeb.GameChannel do
  use DetectiveWeb, :channel

  alias Detective.Games
  alias Detective.Games.{Command, GameBroadcaster, Session}

  @impl true
  def join("game:" <> game_id, _payload, socket) do
    case Games.game_projection(socket.assigns.current_scope, game_id) do
      {:ok, projection} ->
        {:ok, %{state: projection.public}, assign(socket, :game_id, projection.public.game_id)}

      {:error, reason} ->
        {:error, %{code: error_code(reason)}}
    end
  end

  @impl true
  def handle_in(
        "command",
        %{
          "command_id" => command_id,
          "type" => type,
          "expected_version" => expected_version,
          "payload" => payload
        },
        socket
      ) do
    with {:ok, command} <- Command.build(command_id, type, expected_version, payload),
         {:ok, reply} <-
           Session.execute(socket.assigns.game_id, socket.assigns.user_id, command),
         {:ok, state} <- Session.get_state(socket.assigns.game_id),
         :ok <- GameBroadcaster.broadcast(state, reply.events) do
      {:reply,
       {:ok,
        %{
          version: reply.version,
          duplicate: reply.duplicate
        }}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{code: error_code(reason)}}, socket}
    end
  end

  def handle_in("command", _payload, socket) do
    {:reply, {:error, %{code: "invalid_command"}}, socket}
  end

  defp error_code(reason)
       when reason in [
              :invalid_command,
              :invalid_game_id,
              :not_a_member,
              :game_not_active,
              :snapshot_not_found,
              :stale_version,
              :wrong_phase,
              :wrong_role,
              :not_your_turn,
              :already_placed,
              :placement_required,
              :invalid_location,
              :police_station_required,
              :no_actions_remaining,
              :already_at_location,
              :destination_outside_district,
              :mob_joint_required,
              :kickback_already_used,
              :command_not_allowed,
              :command_id_conflict
            ],
       do: Atom.to_string(reason)

  defp error_code(_reason), do: "unavailable"
end
