defmodule Detective.Games.GameBroadcaster do
  @moduledoc false

  alias Detective.Games.Event
  alias Detective.Games.Projections
  alias Detective.Games.Projections.Public
  alias Detective.Games.State
  alias DetectiveWeb.Endpoint

  @public_event_names %{
    detective_placed: "detective_placed",
    player_moved: "player_moved",
    evidence_analyzed: "evidence_analyzed",
    kickback_collected: "kickback_collected",
    location_searched: "location_searched",
    suspect_searched: "suspect_searched",
    evidence_submitted: "evidence_submitted",
    free_question_declined: "free_question_declined",
    question_allowed: "question_allowed",
    question_blocked: "question_blocked",
    question_abandoned: "question_abandoned",
    goon_bribed: "goon_bribed",
    detective_bribed: "detective_bribed",
    officer_bribed: "officer_bribed",
    snitch_decision_recorded: "snitch_decision_recorded",
    snitch_window_closed: "snitch_window_closed",
    snitches_resolved: "snitches_resolved",
    interrogation_started: "interrogation_started",
    response_published: "response_published",
    response_accepted: "response_accepted",
    challenge_succeeded: "challenge_succeeded",
    challenge_failed: "challenge_failed",
    accusation_submitted: "accusation_submitted",
    accusation_rejected: "accusation_rejected",
    final_guess_submitted: "final_guess_submitted",
    game_finished: "game_finished",
    turn_ended: "turn_ended",
    turn_started: "turn_started",
    day_advanced: "day_advanced",
    accusation_opened: "accusation_opened",
    game_paused: "game_paused",
    game_resumed: "game_resumed"
  }

  def broadcast(%State{} = state, events) when is_list(events) do
    Enum.each(events, &broadcast_event(state, &1))

    Endpoint.broadcast(game_topic(state.game_id), "game_state", %{
      version: state.version,
      state: Public.render(state)
    })

    Enum.each(state.players, fn {_player_id, player} ->
      {:ok, private_projection} = Projections.private_for_user(state, player.user_id)

      Endpoint.broadcast(user_topic(state.game_id, player.user_id), "private_state", %{
        game_id: state.game_id,
        version: state.version,
        state: private_projection
      })
    end)

    :ok
  end

  defp broadcast_event(state, %Event{} = event) do
    event_name = Map.fetch!(@public_event_names, event.type)

    Endpoint.broadcast(game_topic(state.game_id), event_name, %{
      event_id: event.delivery_id,
      version: event.version || state.version,
      payload: event.public_payload
    })

    Enum.each(event.private_payloads, fn {recipient_user_id, payload} ->
      Endpoint.broadcast(user_topic(state.game_id, recipient_user_id), "private_event", %{
        game_id: state.game_id,
        event_id: event.delivery_id,
        version: event.version || state.version,
        type: event_name,
        payload: payload
      })
    end)
  end

  defp game_topic(game_id), do: "game:#{game_id}"
  defp user_topic(game_id, user_id), do: "user:#{user_id}:game:#{game_id}"
end
