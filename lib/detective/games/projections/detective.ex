defmodule Detective.Games.Projections.Detective do
  @moduledoc false

  alias Detective.Cases.{SearchDeck, SpecialActors}
  alias Detective.Games.{Rules, State}

  def render_private(%State{} = state, actor_user_id) do
    case State.player_by_user_id(state, actor_user_id) do
      %{role: "detective"} = player ->
        available_actions = Rules.available_actions(state, actor_user_id)

        %{
          role: "detective",
          player_id: player.id,
          scratch: player.scratch,
          leverage_supply: player.leverage_supply,
          leverage_on_suspects: player.leverage_on_suspects,
          knowledge: player.knowledge,
          statements: Map.get(player, :statements, []),
          search_notes: Map.get(player, :search_notes, []),
          evidence: known_case_cards(state, Map.get(player, :evidence, [])),
          known_case_cards: known_case_cards(state, player.knowledge),
          free_question_suspect_id: Map.get(player, :free_question_suspect_id),
          solve_token_available: Map.get(player, :solve_token_available, true),
          solve_attempt: Map.get(player, :solve_attempt),
          final_guess: Map.get(player, :final_guess),
          accusation_options: Rules.accusation_options(state, player),
          bribe_options: Rules.bribe_options(state, player),
          available_actions: available_actions,
          searchable_suspect_ids:
            state
            |> Rules.searchable_suspects(player)
            |> Enum.map(& &1.id),
          interrogation_options: Rules.interrogation_options(state, player),
          special_actor_interactions:
            SpecialActors.available_interactions(state.special_actors, player),
          pending_interrogation: pending_interrogation(state, player),
          valid_move_location_ids:
            if("move" in available_actions,
              do: state |> Rules.valid_move_destinations(player) |> Enum.map(& &1.id),
              else: []
            ),
          placement_location_ids:
            if("place" in available_actions,
              do: state |> Rules.police_stations() |> Enum.map(& &1.id),
              else: []
            )
        }

      _player ->
        nil
    end
  end

  defp pending_interrogation(
         %State{pending_action: %{"type" => "interrogation"} = pending} = state,
         player
       ) do
    eligible_ids = pending["eligible_snitch_player_ids"] || []

    if pending["detective_player_id"] == player.id or player.id in eligible_ids do
      %{
        id: pending["id"],
        suspect_id: pending["suspect_id"],
        topic_id: pending["topic_id"],
        topic_code: pending["topic_code"],
        stage: pending_stage(pending, state.phase),
        question_blocked: pending["stage"] == "blocked_question",
        snitch_choice: Map.get(pending["snitch_decisions"] || %{}, player.id),
        response_text:
          if(pending["detective_player_id"] == player.id,
            do: pending["selected_response_text"],
            else: nil
          )
      }
    end
  end

  defp pending_interrogation(%State{}, _player), do: nil

  defp known_case_cards(state, card_ids) do
    {:ok, cards} = SearchDeck.case_cards(state.case_definition, card_ids)
    Enum.map(cards, &Map.take(&1, [:id, :code, :title, :type, :description]))
  end

  defp pending_stage(%{"stage" => stage}, _phase), do: stage
  defp pending_stage(_pending, :waiting_for_chisel), do: "response"
  defp pending_stage(_pending, _phase), do: "response_decision"
end
