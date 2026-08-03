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
         :ok <- GameBroadcaster.broadcast(reply.state, reply.events) do
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
              :search_not_available,
              :search_archived,
              :evidence_not_takeable,
              :evidence_unavailable,
              :invalid_case_card,
              :free_question_pending,
              :free_question_not_available,
              :question_block_unavailable,
              :question_not_blocked,
              :insufficient_scratch,
              :not_snitch_eligible,
              :snitch_choice_recorded,
              :invalid_snitch_resolution,
              :insufficient_chisel_leverage,
              :invalid_suspect,
              :suspect_not_at_location,
              :invalid_topic,
              :topic_not_known,
              :response_not_found,
              :invalid_response,
              :response_forced_truthful,
              :suspect_leverage_required,
              :no_leverage_remaining,
              :invalid_pending_action,
              :response_not_selected,
              :not_interrogating_detective,
              :accusation_not_available,
              :invalid_accusation,
              :accusation_must_start_turn,
              :solve_token_spent,
              :accusation_suspect_unknown,
              :accusation_weapon_unknown,
              :final_guess_already_submitted,
              :command_not_allowed,
              :command_id_conflict,
              :unknown_persisted_event,
              :session_unavailable
            ],
       do: Atom.to_string(reason)

  defp error_code(_reason), do: "unavailable"
end
