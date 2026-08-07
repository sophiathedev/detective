defmodule Detective.Games.Projections.Public do
  @moduledoc false

  alias Detective.Cases.{AccusationSheet, ResponseMatrix, SpecialActors, SpecialRules}
  alias Detective.Games.State

  def render(%State{} = state) do
    %{
      game_id: state.game_id,
      status: Atom.to_string(state.status),
      phase: Atom.to_string(state.phase),
      version: state.version,
      day: state.day,
      days_remaining: state.days_remaining,
      pause:
        if(state.status == :paused,
          do: %{
            reason: Atom.to_string(state.pause_reason),
            player_ids: state.paused_player_ids,
            previous_phase: Atom.to_string(state.paused_from_phase)
          },
          else: nil
        ),
      current_detective_id: state.current_detective_id,
      briefing: state.case_definition["briefing"],
      players: public_players(state),
      locations: public_locations(state),
      suspects: public_suspects(state),
      special_actors: SpecialActors.public_actors(state.special_actors),
      case_cards: public_case_cards(state),
      case_card_slots: public_case_card_slots(state),
      archived_searches: state.archived_searches,
      taken_evidence: public_taken_evidence(state),
      special_rules:
        SpecialRules.public_rules(state.case_definition, state.triggered_special_rule_ids),
      pending_interrogation: pending_interrogation(state),
      winner: state.winner,
      result: public_result(state),
      public_history: state.public_history
    }
  end

  defp public_players(state) do
    state.players
    |> Map.values()
    |> Enum.sort_by(fn player -> {player.role != "chisel", player[:seat] || 0} end)
    |> Enum.map(fn
      %{role: "detective"} = player ->
        %{
          id: player.id,
          display_name: player.display_name,
          role: "detective",
          seat: player.seat,
          location_id: player.location_id,
          actions_remaining: player.actions_remaining,
          leverage_on_suspects: player.leverage_on_suspects,
          final_guess_submitted: is_map(Map.get(player, :final_guess))
        }

      %{role: "chisel"} = player ->
        %{
          id: player.id,
          display_name: player.display_name,
          role: "chisel"
        }
    end)
  end

  defp public_locations(state) do
    state.locations
    |> Map.values()
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn location ->
      %{
        id: location.id,
        name: location.name,
        type: location.type,
        district_ids: location.district_ids,
        x: location.x,
        y: location.y
      }
    end)
  end

  defp public_suspects(state) do
    state.suspects
    |> Map.values()
    |> Enum.filter(&Map.get(&1, :revealed, true))
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn suspect ->
      %{
        id: suspect.id,
        name: suspect.name,
        occupation: suspect.occupation,
        location_id: suspect.location_id
      }
    end)
  end

  defp public_case_cards(state) do
    state.case_definition
    |> ResponseMatrix.topics()
    |> Enum.filter(&(&1.id in state.public_case_card_ids))
    |> Enum.map(&Map.take(&1, [:id, :code, :title, :type, :description]))
  end

  defp public_case_card_slots(state) do
    detectives =
      state.players
      |> Map.values()
      |> Enum.filter(&(&1.role == "detective"))
      |> Enum.sort_by(& &1.seat)

    state.case_definition
    |> ResponseMatrix.topics()
    |> Enum.with_index(1)
    |> Enum.map(fn {card, position} ->
      faceup? = card.id in state.public_case_card_ids
      taken = Map.get(state.taken_evidence, card.id)

      knowledge_player_ids =
        if faceup? do
          []
        else
          detectives
          |> Enum.filter(&(card.id in &1.knowledge))
          |> Enum.map(& &1.id)
        end

      slot = %{
        code: card.code,
        position: position,
        status: case_card_status(faceup?, taken),
        knowledge_player_ids: knowledge_player_ids,
        evidence_holder_player_id: taken && taken["player_id"],
        evidence_release_day: taken && taken["release_day"]
      }

      if faceup? do
        Map.merge(slot, %{title: card.title, type: card.type})
      else
        slot
      end
    end)
  end

  defp case_card_status(_faceup?, taken) when is_map(taken), do: "removed"
  defp case_card_status(true, _taken), do: "faceup"
  defp case_card_status(false, _taken), do: "facedown"

  defp public_taken_evidence(state) do
    state.taken_evidence
    |> Map.values()
    |> Enum.map(fn evidence ->
      %{
        holder_player_id: evidence["player_id"],
        release_day: evidence["release_day"]
      }
    end)
  end

  defp pending_interrogation(
         %State{pending_action: %{"type" => "interrogation"} = pending} = state
       ) do
    stage = pending_stage(pending, state.phase)

    %{
      id: pending["id"],
      detective_player_id: pending["detective_player_id"],
      suspect_id: pending["suspect_id"],
      topic_code: pending["topic_code"],
      stage: stage,
      snitch_decisions_recorded: map_size(pending["snitch_decisions"] || %{}),
      snitch_decisions_required: length(pending["eligible_snitch_player_ids"] || []),
      snitch_request_count: public_snitch_request_count(pending, stage),
      response_delivered: is_binary(pending["selected_response_id"])
    }
  end

  defp pending_interrogation(%State{}), do: nil

  defp pending_stage(%{"stage" => "block_decision"}, _phase), do: "awaiting_chisel_block"
  defp pending_stage(%{"stage" => "blocked_question"}, _phase), do: "question_blocked"
  defp pending_stage(%{"stage" => "snitch_decisions"}, _phase), do: "awaiting_snitches"
  defp pending_stage(%{"stage" => "snitch_block"}, _phase), do: "awaiting_chisel_snitch_block"
  defp pending_stage(%{"stage" => "response"}, _phase), do: "awaiting_chisel_response"
  defp pending_stage(%{"stage" => "response_decision"}, _phase), do: "awaiting_detective_decision"
  defp pending_stage(_pending, :waiting_for_chisel), do: "awaiting_chisel_response"
  defp pending_stage(_pending, _phase), do: "awaiting_detective_decision"

  defp public_snitch_request_count(pending, stage)
       when stage in [
              "awaiting_chisel_snitch_block",
              "awaiting_chisel_response",
              "awaiting_detective_decision"
            ] do
    pending
    |> Map.get("snitch_decisions", %{})
    |> Map.values()
    |> Enum.count(&(&1 == true))
  end

  defp public_snitch_request_count(_pending, _stage), do: nil

  defp public_result(%State{status: :finished} = state) do
    debrief = %{
      winner: state.winner,
      detectives: detective_debriefs(state),
      investigation: investigation_debrief(state)
    }

    case AccusationSheet.revealed_solution(state.case_definition) do
      {:ok, solution} ->
        Map.merge(debrief, %{
          solution: solution,
          epilogue: state.case_definition["epilogue"]
        })

      {:error, _reason} ->
        debrief
    end
  end

  defp public_result(%State{}), do: nil

  defp detective_debriefs(state) do
    Enum.map(state.detective_order, fn player_id ->
      detective = Map.fetch!(state.players, player_id)

      %{
        player_id: detective.id,
        display_name: detective.display_name,
        seat: detective.seat,
        won: state.winner["player_id"] == detective.id,
        solve_attempt: revealed_guess(state.case_definition, Map.get(detective, :solve_attempt)),
        final_guess: revealed_guess(state.case_definition, Map.get(detective, :final_guess)),
        activity: player_activity(state.public_history, detective.id)
      }
    end)
  end

  defp revealed_guess(case_definition, guess) when is_map(guess) do
    case AccusationSheet.revealed_guess(case_definition, guess) do
      {:ok, revealed} -> revealed
      {:error, _reason} -> nil
    end
  end

  defp revealed_guess(_case_definition, _guess), do: nil

  defp investigation_debrief(state) do
    %{
      days_elapsed: state.day,
      moves: count_history(state.public_history, ["player_moved"]),
      searches: count_history(state.public_history, ["location_searched", "suspect_searched"]),
      interrogations: count_history(state.public_history, ["interrogation_started"]),
      challenges:
        count_history(state.public_history, ["challenge_succeeded", "challenge_failed"]),
      successful_challenges: count_history(state.public_history, ["challenge_succeeded"]),
      public_leads: length(state.public_case_card_ids),
      evidence_taken: map_size(state.taken_evidence)
    }
  end

  defp player_activity(history, player_id) do
    %{
      moves: count_history(history, ["player_moved"], player_id),
      searches: count_history(history, ["location_searched", "suspect_searched"], player_id),
      interrogations: count_history(history, ["interrogation_started"], player_id),
      challenges: count_history(history, ["challenge_succeeded", "challenge_failed"], player_id)
    }
  end

  defp count_history(history, types, player_id \\ nil) do
    Enum.count(history, fn entry ->
      history_value(entry, :type) in types and
        (is_nil(player_id) or history_value(entry, :player_id) == player_id)
    end)
  end

  defp history_value(entry, key),
    do: Map.get(entry, key) || Map.get(entry, Atom.to_string(key))
end
