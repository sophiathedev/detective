defmodule Detective.Games.Rules do
  @moduledoc """
  Pure queries for turn actions and district-based movement.
  """

  alias Detective.Cases.ResponseMatrix
  alias Detective.Games.State

  def available_actions(%State{} = state, actor_user_id) do
    case State.player_by_user_id(state, actor_user_id) do
      %{id: player_id, role: "detective"} = player
      when player_id == state.current_detective_id and state.phase == :detective_turn ->
        detective_actions(state, player)

      %{id: player_id, role: "detective"} = player
      when player_id == state.current_detective_id and
             state.phase == :waiting_for_detective_decision ->
        decision_actions(state, player)

      %{role: "chisel"} when state.phase == :waiting_for_chisel ->
        ["select_response"]

      _other ->
        []
    end
  end

  def interrogation_options(%State{} = state, %{role: "detective"} = player) do
    if player.location_id && player.actions_remaining > 0 do
      known_topics = ResponseMatrix.known_topics(state.case_definition, player.knowledge)

      state.suspects
      |> Map.values()
      |> Enum.filter(&(&1.location_id == player.location_id))
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

  def same_district?(location_a, location_b) do
    location_a.district_ids
    |> MapSet.new()
    |> MapSet.disjoint?(MapSet.new(location_b.district_ids))
    |> Kernel.not()
  end

  defp detective_actions(_state, %{location_id: nil}), do: ["place"]

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

    current_location = Map.get(state.locations, player.location_id)

    if player.actions_remaining > 0 and current_location.type == "mob_joint" and
         player.kickback_day != state.day do
      ["kickback" | actions]
    else
      actions
    end
  end

  defp decision_actions(state, player) do
    pending = state.pending_action

    if is_map(pending) and pending["detective_player_id"] == player.id and
         is_binary(pending["selected_response_id"]) do
      actions = ["accept_response"]

      if player.leverage_supply > 0 do
        ["challenge_response" | actions]
      else
        actions
      end
    else
      []
    end
  end
end
