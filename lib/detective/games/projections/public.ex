defmodule Detective.Games.Projections.Public do
  @moduledoc false

  alias Detective.Cases.{AccusationSheet, ResponseMatrix}
  alias Detective.Games.State

  def render(%State{} = state) do
    %{
      game_id: state.game_id,
      status: Atom.to_string(state.status),
      phase: Atom.to_string(state.phase),
      version: state.version,
      day: state.day,
      days_remaining: state.days_remaining,
      current_detective_id: state.current_detective_id,
      players: public_players(state),
      locations: public_locations(state),
      suspects: public_suspects(state),
      case_cards: public_case_cards(state),
      archived_searches: state.archived_searches,
      taken_evidence: public_taken_evidence(state),
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
          leverage_on_suspects: player.leverage_on_suspects
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
    case AccusationSheet.revealed_solution(state.case_definition) do
      {:ok, solution} ->
        %{
          winner: state.winner,
          solution: solution,
          epilogue: state.case_definition["epilogue"]
        }

      {:error, _reason} ->
        %{winner: state.winner}
    end
  end

  defp public_result(%State{}), do: nil
end
