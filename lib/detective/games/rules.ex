defmodule Detective.Games.Rules do
  @moduledoc """
  Pure queries for turn actions and district-based movement.
  """

  alias Detective.Cases.{AccusationSheet, ResponseMatrix, SearchDeck, SpecialActors}
  alias Detective.Games.State

  def available_actions(%State{} = state, actor_user_id) do
    actor = State.player_by_user_id(state, actor_user_id)

    actions =
      case actor do
        %{role: "detective"} when state.status == :paused ->
          []

        %{role: "chisel"} when state.status == :paused ->
          ["resume_game"]

        %{id: player_id, role: "detective"} = player
        when player_id == state.current_detective_id and state.phase == :detective_turn ->
          detective_actions(state, player)

        %{id: player_id, role: "detective"} = player
        when player_id == state.current_detective_id and
               state.phase == :waiting_for_detective_decision ->
          blocked_or_response_actions(state, player)

        %{role: "detective"} = player when state.phase == :waiting_for_snitches ->
          snitch_actions(state, player)

        %{role: "detective"} = player when state.phase == :accusation ->
          if is_nil(Map.get(player, :final_guess)) and accusation_ready?(state, player),
            do: ["submit_final_guess"],
            else: []

        %{role: "chisel"} = player when state.phase == :waiting_for_chisel ->
          chisel_actions(state, player)

        _other ->
          []
      end

    if match?(%{role: "chisel"}, actor) and state.status in [:active, :paused] do
      Enum.uniq(["concede_game" | actions])
    else
      actions
    end
  end

  def interrogation_options(%State{} = state, %{role: "detective"} = player) do
    free_question_suspect_id = Map.get(player, :free_question_suspect_id)
    can_question? = player.actions_remaining > 0 or is_binary(free_question_suspect_id)

    if player.location_id && can_question? &&
         not SpecialActors.blocks_action?(state.special_actors, player.location_id, "interrogate") do
      known_topics = ResponseMatrix.known_topics(state.case_definition, player.knowledge)

      state.suspects
      |> Map.values()
      |> Enum.filter(fn suspect ->
        Map.get(suspect, :revealed, true) and suspect.location_id == player.location_id and
          (is_nil(free_question_suspect_id) or free_question_suspect_id == suspect.id)
      end)
      |> Enum.map(fn suspect ->
        topics =
          Enum.filter(known_topics, fn topic ->
            match?(
              {:ok, [_most_useful | _misdirections]},
              ResponseMatrix.response_options(state.case_definition, suspect.id, topic.id)
            )
          end)

        %{
          suspect_id: suspect.id,
          suspect_name: suspect.name,
          topics: Enum.map(topics, &Map.take(&1, [:id, :code, :title, :type]))
        }
      end)
      |> Enum.reject(&(&1.topics == []))
      |> Enum.sort_by(& &1.suspect_name)
    else
      []
    end
  end

  def interrogation_options(%State{}, _player), do: []

  def valid_move_destinations(%State{}, %{location_id: nil}), do: []

  def valid_move_destinations(%State{} = state, player) do
    case Map.get(state.locations, player.location_id) do
      nil ->
        []

      current_location ->
        state.locations
        |> Map.values()
        |> Enum.filter(fn location ->
          location.id != current_location.id and same_district?(current_location, location)
        end)
        |> Enum.sort_by(& &1.name)
    end
  end

  def police_stations(%State{} = state) do
    state.locations
    |> Map.values()
    |> Enum.filter(&(&1.type == "police_station"))
    |> Enum.sort_by(& &1.name)
  end

  def searchable_suspects(%State{} = state, %{role: "detective"} = player) do
    if player.location_id && player.actions_remaining > 0 &&
         not SpecialActors.blocks_action?(
           state.special_actors,
           player.location_id,
           "search_suspect"
         ) &&
         SearchDeck.configured?(state.case_definition) do
      state.suspects
      |> Map.values()
      |> Enum.filter(fn suspect ->
        Map.get(suspect, :revealed, true) and suspect.location_id == player.location_id and
          "suspect:#{suspect.id}" not in state.archived_searches and
          match?({:ok, _result}, SearchDeck.suspect_result(state.case_definition, suspect.id))
      end)
      |> Enum.sort_by(& &1.name)
    else
      []
    end
  end

  def searchable_suspects(%State{}, _player), do: []

  def same_district?(location_a, location_b) do
    location_a.district_ids
    |> MapSet.new()
    |> MapSet.disjoint?(MapSet.new(location_b.district_ids))
    |> Kernel.not()
  end

  def accusation_options(%State{} = state, %{role: "detective"} = player) do
    revealed_suspect_ids =
      state.suspects
      |> Map.values()
      |> Enum.filter(&Map.get(&1, :revealed, true))
      |> Enum.map(& &1.id)

    AccusationSheet.public_options(
      state.case_definition,
      player.knowledge,
      revealed_suspect_ids
    )
  end

  def accusation_options(%State{}, _player),
    do: %{suspects: [], weapons: [], motives: []}

  def bribe_options(%State{} = state, %{role: "detective"} = player) do
    other_detectives =
      state.detective_order
      |> Enum.reject(&(&1 == player.id))
      |> Enum.map(&Map.fetch!(state.players, &1))

    detective_targets =
      other_detectives
      |> Enum.filter(&(&1.location_id == player.location_id and not is_nil(player.location_id)))
      |> Enum.map(fn detective ->
        %{
          player_id: detective.id,
          display_name: detective.display_name,
          case_cards: sealed_case_card_refs(state, private_unknown_ids(state, player, detective))
        }
      end)
      |> Enum.reject(&(&1.case_cards == []))

    holders_by_card_id =
      Enum.reduce(other_detectives, %{}, fn detective, acc ->
        holder = %{player_id: detective.id, display_name: detective.display_name}

        Enum.reduce(private_unknown_ids(state, player, detective), acc, fn card_id, holders ->
          Map.update(holders, card_id, [holder], &[holder | &1])
        end)
      end)

    officer_case_cards =
      state
      |> sealed_case_card_refs(Map.keys(holders_by_card_id))
      |> Enum.map(fn card ->
        Map.put(card, :known_by, holders_by_card_id |> Map.fetch!(card.id) |> Enum.reverse())
      end)

    %{detective_targets: detective_targets, officer_case_cards: officer_case_cards}
  end

  def bribe_options(%State{}, _player),
    do: %{detective_targets: [], officer_case_cards: []}

  defp detective_actions(_state, %{location_id: nil}), do: ["place"]

  defp detective_actions(state, %{free_question_suspect_id: suspect_id} = player)
       when is_binary(suspect_id) do
    if interrogation_options(state, player) == [] do
      ["skip_free_question"]
    else
      ["interrogate", "skip_free_question"]
    end
  end

  defp detective_actions(state, player) do
    actions = ["end_turn"]

    actions =
      if player.actions_remaining > 0 do
        ["analyze" | actions]
      else
        actions
      end

    actions =
      if player.actions_remaining > 0 and valid_move_destinations(state, player) != [] do
        ["move" | actions]
      else
        actions
      end

    actions =
      if player.actions_remaining > 0 and interrogation_options(state, player) != [] do
        ["interrogate" | actions]
      else
        actions
      end

    actions =
      if player.actions_remaining > 0 and SearchDeck.configured?(state.case_definition) and
           not SpecialActors.blocks_action?(
             state.special_actors,
             player.location_id,
             "search_location"
           ) and
           "location:#{player.location_id}" not in state.archived_searches do
        ["search_location" | actions]
      else
        actions
      end

    actions =
      if searchable_suspects(state, player) != [] do
        ["search_suspect" | actions]
      else
        actions
      end

    current_location = Map.get(state.locations, player.location_id)

    actions =
      if player.actions_remaining > 0 and current_location.type == "mob_joint" and
           player.kickback_day != state.day do
        ["kickback" | actions]
      else
        actions
      end

    bribe_options = bribe_options(state, player)

    actions =
      if player.scratch >= 2 and bribe_options.detective_targets != [] do
        ["bribe_detective" | actions]
      else
        actions
      end

    actions =
      if player.scratch >= 3 and current_location.type == "police_station" and
           bribe_options.officer_case_cards != [] do
        ["bribe_officer" | actions]
      else
        actions
      end

    actions =
      if SpecialActors.available_interactions(state.special_actors, player) != [] do
        ["interact_special_actor" | actions]
      else
        actions
      end

    if Map.get(player, :solve_token_available, true) and
         player.actions_remaining == 4 and accusation_ready?(state, player) do
      ["accuse" | actions]
    else
      actions
    end
  end

  defp blocked_or_response_actions(state, player) do
    pending = state.pending_action

    cond do
      not is_map(pending) or pending["detective_player_id"] != player.id ->
        []

      pending_stage(pending) == "blocked_question" ->
        if player.scratch >= 2,
          do: ["bribe_goon", "accept_question_block"],
          else: ["accept_question_block"]

      pending_stage(pending) == "response_decision" and
          is_binary(pending["selected_response_id"]) ->
        actions = ["accept_response"]

        if player.leverage_supply > 0 do
          ["challenge_response" | actions]
        else
          actions
        end

      true ->
        []
    end
  end

  defp snitch_actions(state, player) do
    pending = state.pending_action || %{}
    eligible_ids = pending["eligible_snitch_player_ids"] || []
    decisions = pending["snitch_decisions"] || %{}

    if player.id in eligible_ids and not Map.has_key?(decisions, player.id) do
      ["choose_snitch", "decline_snitch"]
    else
      []
    end
  end

  defp chisel_actions(state, player) do
    pending = state.pending_action || %{}

    case pending_stage(pending) do
      "block_decision" ->
        detective_id = pending["detective_player_id"]
        actions = ["allow_question"]

        if Map.get(player.leverage_by_detective, detective_id, 0) > 0,
          do: ["block_question" | actions],
          else: actions

      "snitch_block" ->
        ["resolve_snitches"]

      "response" ->
        ["select_response"]

      _stage ->
        []
    end
  end

  defp pending_stage(%{"stage" => stage}) when is_binary(stage), do: stage

  defp pending_stage(%{"selected_response_id" => response_id}) when is_binary(response_id),
    do: "response_decision"

  defp pending_stage(%{"type" => "interrogation"}), do: "response"
  defp pending_stage(_pending), do: nil

  defp accusation_ready?(state, player) do
    options = accusation_options(state, player)
    options.suspects != [] and options.weapons != [] and options.motives != []
  end

  defp private_unknown_ids(state, player, other_detective) do
    other_detective.knowledge
    |> Enum.reject(&(&1 in player.knowledge or &1 in state.public_case_card_ids))
    |> Enum.uniq()
  end

  defp sealed_case_card_refs(state, card_ids) do
    case SearchDeck.case_cards(state.case_definition, card_ids) do
      {:ok, cards} ->
        cards
        |> Enum.map(&Map.take(&1, [:id, :code]))
        |> Enum.sort_by(& &1.code)

      {:error, _reason} ->
        []
    end
  end
end
