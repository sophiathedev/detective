defmodule Detective.Games.Projections.Chisel do
  @moduledoc false

  alias Detective.Games.State

  def render_private(%State{} = state, actor_user_id) do
    case State.player_by_user_id(state, actor_user_id) do
      %{role: "chisel"} = player ->
        %{
          role: "chisel",
          player_id: player.id,
          leverage_by_detective: player.leverage_by_detective,
          pending_action: state.pending_action,
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
end
