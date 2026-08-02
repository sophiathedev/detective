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
      pending_interrogation: pending_interrogation(state),
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

  defp pending_interrogation(
         %State{pending_action: %{"type" => "interrogation"} = pending} = state
       ) do
    %{
      id: pending["id"],
      detective_player_id: pending["detective_player_id"],
      suspect_id: pending["suspect_id"],
      topic_code: pending["topic_code"],
      stage:
        if(state.phase == :waiting_for_chisel,
          do: "awaiting_chisel",
          else: "awaiting_detective_decision"
        ),
      response_delivered: is_binary(pending["selected_response_id"])
    }
  end

  defp pending_interrogation(%State{}), do: nil
end
