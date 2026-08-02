defmodule Detective.Games.Projections.Chisel do
  @moduledoc false

  alias Detective.Cases.ResponseMatrix
  alias Detective.Games.{Rules, State}

  def render_private(%State{} = state, actor_user_id) do
    case State.player_by_user_id(state, actor_user_id) do
      %{role: "chisel"} = player ->
        %{
          role: "chisel",
          player_id: player.id,
          leverage_by_detective: player.leverage_by_detective,
          available_actions: Rules.available_actions(state, actor_user_id),
          pending_interrogation: pending_interrogation(state),
          casebook: %{
            briefing: state.case_definition["briefing"],
            solution: state.case_definition["solution"],
            response_matrix: state.case_definition["response_matrix"]
          }
        }

      _player ->
        nil
    end
  end

  defp pending_interrogation(
         %State{pending_action: %{"type" => "interrogation"} = pending} = state
       ) do
    suspect = Map.fetch!(state.suspects, pending["suspect_id"])
    detective = Map.fetch!(state.players, pending["detective_player_id"])
    {:ok, topic} = ResponseMatrix.topic(state.case_definition, pending["topic_id"])

    {:ok, options} =
      ResponseMatrix.response_options(state.case_definition, suspect.id, topic.id)

    %{
      id: pending["id"],
      detective: %{id: detective.id, display_name: detective.display_name},
      suspect: %{id: suspect.id, name: suspect.name},
      topic: Map.take(topic, [:id, :code, :title, :type]),
      stage:
        if(state.phase == :waiting_for_chisel,
          do: "awaiting_chisel",
          else: "awaiting_detective_decision"
        ),
      forced_truthful: pending["forced_truthful"],
      selected_response:
        if(is_binary(pending["selected_response_id"]),
          do: %{
            id: pending["selected_response_id"],
            text: pending["selected_response_text"],
            type: pending["selected_response_type"]
          },
          else: nil
        ),
      response_options:
        if(state.phase == :waiting_for_chisel,
          do: options,
          else: []
        )
    }
  end

  defp pending_interrogation(%State{}), do: nil
end
