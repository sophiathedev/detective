defmodule Detective.Games.Projections.Public do
  @moduledoc false

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
end
