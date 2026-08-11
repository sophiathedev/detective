defmodule Detective.Games.InvestigationStatsTest do
  use ExUnit.Case, async: true

  alias Detective.Games.InvestigationStats

  test "keeps cumulative totals after the retained history window is exceeded" do
    player_id = Ecto.UUID.generate()

    stats =
      Enum.reduce(1..125, InvestigationStats.empty(), fn _index, stats ->
        InvestigationStats.record(stats, %{type: "player_moved", player_id: player_id})
      end)

    assert InvestigationStats.investigation(stats).moves == 125
    assert InvestigationStats.player_activity(stats, player_id).moves == 125
  end

  test "tracks challenge totals and successes separately" do
    player_id = Ecto.UUID.generate()

    stats =
      InvestigationStats.empty()
      |> InvestigationStats.record(%{type: "challenge_succeeded", player_id: player_id})
      |> InvestigationStats.record(%{type: "challenge_failed", player_id: player_id})

    assert InvestigationStats.investigation(stats) == %{
             moves: 0,
             searches: 0,
             interrogations: 0,
             challenges: 2,
             successful_challenges: 1
           }

    assert InvestigationStats.player_activity(stats, player_id).challenges == 2
  end
end
