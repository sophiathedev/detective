defmodule DetectiveWeb.GameChannel do
  use DetectiveWeb, :channel

  alias Detective.Games
  alias Detective.Games.{Command, ConnectionMonitor, GameBroadcaster, Session}
  alias Detective.Security.RateLimiter
  alias DetectiveWeb.Presence

  @command_limit 12
  @sync_limit 10
  @rate_window_ms 2_000

  @impl true
  def join("game:" <> game_id, _payload, socket) do
    case Games.game_projection(socket.assigns.current_scope, game_id) do
      {:ok, projection} ->
        game_status =
          case projection.public.status do
            "active" -> :active
            "paused" -> :paused
            "finished" -> :finished
          end

        socket =
          socket
          |> assign(:game_id, projection.public.game_id)
          |> assign(:player_id, projection.private.player_id)
          |> assign(:game_player_ids, Enum.map(projection.public.players, & &1.id))
          |> assign(:game_status, game_status)
          |> assign(:game_version, projection.public.version)

        send(self(), :after_join)
        {:ok, %{state: projection.public}, socket}

      {:error, reason} ->
        {:error, %{code: error_code(reason)}}
    end
  end

  @impl true
  def handle_info(:after_join, %{assigns: %{game_status: :finished}} = socket) do
    {:noreply, socket}
  end

  def handle_info(:after_join, socket) do
    {:ok, _pid} =
      ConnectionMonitor.ensure_monitor(
        socket.assigns.game_id,
        socket.assigns.game_player_ids,
        socket.assigns.game_status,
        socket.assigns.game_version
      )

    {:ok, _ref} =
      Presence.track(
        self(),
        ConnectionMonitor.presence_topic(socket.assigns.game_id),
        socket.assigns.player_id,
        %{online_at: System.system_time(:second)}
      )

    _state = ConnectionMonitor.sync(socket.assigns.game_id)
    {:noreply, socket}
  end

  @impl true
  def handle_in("sync_state", _payload, socket) do
    with :ok <- rate_limit(socket, :public_sync, @sync_limit),
         {:ok, projection} <-
           Games.game_projection(socket.assigns.current_scope, socket.assigns.game_id) do
      {:reply,
       {:ok,
        %{
          version: projection.public.version,
          state: projection.public
        }}, socket}
    else
      {:error, reason} -> {:reply, {:error, %{code: error_code(reason)}}, socket}
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
    with :ok <- rate_limit(socket, :game_command, @command_limit),
         {:ok, command} <- Command.build(command_id, type, expected_version, payload),
         {:ok, reply} <-
           Session.execute(socket.assigns.game_id, socket.assigns.user_id, command),
         :ok <- broadcast_new_command(reply) do
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
    _result = rate_limit(socket, :game_command, @command_limit)
    {:reply, {:error, %{code: "invalid_command"}}, socket}
  end

  def handle_in(_event, _payload, socket) do
    _result = rate_limit(socket, :game_command, @command_limit)
    {:reply, {:error, %{code: "invalid_command"}}, socket}
  end

  defp broadcast_new_command(%{duplicate: true}), do: :ok

  defp broadcast_new_command(%{duplicate: false, state: state, events: events}) do
    GameBroadcaster.broadcast(state, events)
  end

  defp rate_limit(socket, action, limit) do
    RateLimiter.check(
      {action, socket.assigns.user_id, socket.assigns.game_id},
      limit: limit,
      window_ms: @rate_window_ms
    )
  end

  defp error_code(reason)
       when reason in [
              :invalid_command,
              :invalid_game_id,
              :not_a_member,
              :game_not_active,
              :game_not_paused,
              :game_paused,
              :players_offline,
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
              :session_unavailable,
              :rate_limited
            ],
       do: Atom.to_string(reason)

  defp error_code(_reason), do: "unavailable"
end
