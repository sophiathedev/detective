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
          leverage_on_suspects: player.leverage_on_suspects,
          knowledge: player.knowledge,
          statements: Map.get(player, :statements, []),
          available_actions: Rules.available_actions(state, actor_user_id),
          interrogation_options: Rules.interrogation_options(state, player),
          pending_interrogation: pending_interrogation(state, player),
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

  defp pending_interrogation(
         %State{pending_action: %{"type" => "interrogation"} = pending} = state,
         player
       ) do
    if pending["detective_player_id"] == player.id do
      %{
        id: pending["id"],
        suspect_id: pending["suspect_id"],
        topic_id: pending["topic_id"],
        topic_code: pending["topic_code"],
        stage:
          if(state.phase == :waiting_for_chisel,
            do: "awaiting_chisel",
            else: "awaiting_detective_decision"
          ),
        response_text: pending["selected_response_text"]
      }
    end
  end

  defp pending_interrogation(%State{}, _player), do: nil
end
