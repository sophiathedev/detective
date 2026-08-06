defmodule Detective.Games.Projections.Chisel do
  @moduledoc false

  alias Detective.Cases.{ResponseMatrix, SpecialRules}
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
            suspects: state.case_definition["suspects"] || [],
            response_matrix: state.case_definition["response_matrix"],
            search_results: state.case_definition["search_results"],
            case_cards: state.case_definition["case_cards"],
            special_actors: state.case_definition["special_actors"] || [],
            special_rules: SpecialRules.chisel_rules(state.case_definition),
            accusation_options: state.case_definition["accusation_options"],
            epilogue: state.case_definition["epilogue"]
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

    stage = pending_stage(pending, state.phase)
    snitch_ids = snitch_player_ids(pending)

    %{
      id: pending["id"],
      detective: %{id: detective.id, display_name: detective.display_name},
      suspect: %{id: suspect.id, name: suspect.name},
      topic: Map.take(topic, [:id, :code, :title, :type]),
      stage: stage,
      can_block_question:
        stage == "block_decision" and
          Map.get(
            Map.fetch!(state.players, state.chisel_player_id).leverage_by_detective,
            detective.id,
            0
          ) > 0,
      snitch_requests:
        if(stage == "snitch_block",
          do:
            Enum.map(snitch_ids, fn player_id ->
              snitch = Map.fetch!(state.players, player_id)

              %{
                player_id: player_id,
                display_name: snitch.display_name,
                can_block:
                  Map.get(
                    Map.fetch!(state.players, state.chisel_player_id).leverage_by_detective,
                    player_id,
                    0
                  ) > 0
              }
            end),
          else: []
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
        if(stage == "response",
          do: options,
          else: []
        )
    }
  end

  defp pending_interrogation(%State{}), do: nil

  defp pending_stage(%{"stage" => stage}, _phase), do: stage
  defp pending_stage(_pending, :waiting_for_chisel), do: "response"
  defp pending_stage(_pending, _phase), do: "response_decision"

  defp snitch_player_ids(pending) do
    decisions = pending["snitch_decisions"] || %{}

    pending
    |> Map.get("eligible_snitch_player_ids", [])
    |> Enum.filter(&(Map.get(decisions, &1) == true))
  end
end
