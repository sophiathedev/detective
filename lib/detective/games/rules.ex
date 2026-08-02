defmodule Detective.Games.Rules do
  @moduledoc """
  Pure queries for turn actions and district-based movement.
  """

  alias Detective.Games.State

  def available_actions(%State{} = state, actor_user_id) do
    case State.player_by_user_id(state, actor_user_id) do
      %{id: player_id, role: "detective"} = player
      when player_id == state.current_detective_id and state.phase == :detective_turn ->
        detective_actions(state, player)

      _other ->
        []
    end
  end

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

    current_location = Map.get(state.locations, player.location_id)

    if player.actions_remaining > 0 and current_location.type == "mob_joint" and
         player.kickback_day != state.day do
      ["kickback" | actions]
    else
      actions
    end
  end
end
