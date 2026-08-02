defmodule Detective.Games.Projections.Detective do
  @moduledoc false

  alias Detective.Games.{Rules, State}

  def render_private(%State{} = state, actor_user_id) do
    case State.player_by_user_id(state, actor_user_id) do
      %{role: "detective"} = player ->
        %{
          role: "detective",
          player_id: player.id,
          scratch: player.scratch,
          leverage_supply: player.leverage_supply,
          knowledge: player.knowledge,
          available_actions: Rules.available_actions(state, actor_user_id),
          valid_move_location_ids:
            state
            |> Rules.valid_move_destinations(player)
            |> Enum.map(& &1.id),
          placement_location_ids:
            if(player.location_id == nil,
              do: state |> Rules.police_stations() |> Enum.map(& &1.id),
              else: []
            )
        }

      _player ->
        nil
    end
  end
end
