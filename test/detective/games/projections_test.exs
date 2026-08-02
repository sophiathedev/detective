defmodule Detective.Games.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Detective.Games.Projections
  alias Detective.Games.Projections.Public
  alias Detective.Games.State

  test "public and Detective projections never contain Chisel secrets" do
    state = state_fixture()

    public = Public.render(state)
    {:ok, detective} = Projections.for_user(state, detective_user_id())

    public_json = Jason.encode!(public)
    detective_json = Jason.encode!(detective)

    for forbidden <- [
          "solution",
          "response_matrix",
          "most_useful",
          "murderer",
          "user_id",
          "scratch"
        ] do
      refute public_json =~ forbidden
    end

    for forbidden <- ["solution", "response_matrix", "most_useful", "murderer", chisel_user_id()] do
      refute detective_json =~ forbidden
    end

    assert detective.private.scratch == 4
    assert detective.private.available_actions == ["place"]
    assert detective.private.placement_location_ids == ["precinct"]
  end

  test "only the Chisel projection contains the allow-listed secret casebook" do
    state = state_fixture()
    {:ok, chisel} = Projections.for_user(state, chisel_user_id())

    assert chisel.private.role == "chisel"
    assert chisel.private.casebook.solution == %{"suspect_id" => "murderer"}

    assert chisel.private.casebook.response_matrix["suspect"]["topic"]["most_useful"] ==
             "secret answer"

    refute Map.has_key?(chisel.private, :scratch)
    refute Map.has_key?(chisel.private, :actions_remaining)
  end

  defp state_fixture do
    detective_id = "10000000-0000-0000-0000-000000000001"
    chisel_id = "10000000-0000-0000-0000-000000000002"

    %State{
      game_id: Ecto.UUID.generate(),
      case_version_id: Ecto.UUID.generate(),
      days_remaining: 4,
      chisel_player_id: chisel_id,
      current_detective_id: detective_id,
      detective_order: [detective_id],
      players: %{
        detective_id => %{
          id: detective_id,
          user_id: detective_user_id(),
          display_name: "Detective",
          role: "detective",
          seat: 1,
          location_id: nil,
          actions_remaining: 4,
          scratch: 4,
          leverage_supply: 7,
          leverage_on_suspects: %{},
          knowledge: [],
          kickback_day: nil
        },
        chisel_id => %{
          id: chisel_id,
          user_id: chisel_user_id(),
          display_name: "Chisel",
          role: "chisel",
          leverage_by_detective: %{detective_id => 1}
        }
      },
      locations: %{
        "precinct" => %{
          id: "precinct",
          name: "Precinct",
          type: "police_station",
          district_ids: ["central"],
          x: 0.2,
          y: 0.3
        }
      },
      suspects: %{},
      case_definition: %{
        "briefing" => "Private briefing",
        "solution" => %{"suspect_id" => "murderer"},
        "response_matrix" => %{
          "suspect" => %{"topic" => %{"most_useful" => "secret answer"}}
        }
      }
    }
  end

  defp detective_user_id, do: "20000000-0000-0000-0000-000000000001"
  defp chisel_user_id, do: "20000000-0000-0000-0000-000000000002"
end
