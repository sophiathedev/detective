defmodule Detective.Games.State do
  @moduledoc """
  Serializable authoritative state for one game.

  Player entries are maps keyed by game-player ID. The raw case definition is
  server-only and must only leave this struct through projection modules.
  """

  @schema_version 5

  defstruct schema_version: @schema_version,
            game_id: nil,
            case_version_id: nil,
            status: :active,
            phase: :detective_turn,
            paused_from_phase: nil,
            pause_reason: nil,
            paused_player_ids: [],
            version: 0,
            day: 1,
            days_remaining: 0,
            chisel_player_id: nil,
            current_detective_id: nil,
            detective_order: [],
            players: %{},
            locations: %{},
            suspects: %{},
            special_actors: %{},
            case_definition: %{},
            public_case_card_ids: [],
            archived_searches: [],
            taken_evidence: %{},
            triggered_special_rule_ids: [],
            pending_action: nil,
            winner: nil,
            public_history: []

  def schema_version, do: @schema_version

  def player_by_user_id(%__MODULE__{players: players}, user_id) do
    Enum.find_value(players, fn {_player_id, player} ->
      if player.user_id == user_id, do: player
    end)
  end

  def current_detective(%__MODULE__{} = state) do
    Map.get(state.players, state.current_detective_id)
  end
end
