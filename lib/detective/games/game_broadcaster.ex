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
    interrogation_started: "interrogation_started",
    response_published: "response_published",
    response_accepted: "response_accepted",
    challenge_succeeded: "challenge_succeeded",
    challenge_failed: "challenge_failed",
    turn_ended: "turn_ended",
    turn_started: "turn_started",
    day_advanced: "day_advanced",
    accusation_opened: "accusation_opened"
  }

  def broadcast(%State{} = state, events) when is_list(events) do
    Enum.each(events, &broadcast_event(state, &1))

    Endpoint.broadcast(game_topic(state.game_id), "game_state", %{
      version: state.version,
      state: Public.render(state)
    })

    Enum.each(state.players, fn {_player_id, player} ->
      {:ok, private_projection} = Projections.private_for_user(state, player.user_id)

      Endpoint.broadcast(user_topic(player.user_id), "private_state", %{
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
      Endpoint.broadcast(user_topic(recipient_user_id), "private_event", %{
        game_id: state.game_id,
        event_id: event.delivery_id,
        version: event.version || state.version,
        type: event_name,
        payload: payload
      })
    end)
  end

  defp game_topic(game_id), do: "game:#{game_id}"
  defp user_topic(user_id), do: "user:#{user_id}"
end
