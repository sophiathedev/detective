defmodule Detective.Cases.LegacyBoardAdapterTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.LegacyBoardAdapter

  @legacy_ids ~w(
    central-precinct
    meridian-array
    northlight-boarding-house
    city-archive
    telegraph-exchange
    harbor-precinct
    breakwater-relay
    mariner-social-club
  )

  @canonical_ids ~w(51 29 38 48 82 84 99 96)

  test "upgrades the exact published seed topology and every location reference" do
    suspects =
      Enum.with_index(@legacy_ids, 1)
      |> Enum.map(fn {location_id, index} ->
        %{"id" => "suspect-#{index}", "location_id" => location_id}
      end)

    search_locations = Map.new(@legacy_ids, &{&1, %{"text" => &1}})

    legacy = %{
      "locations" => legacy_seed_locations(),
      "suspects" => suspects,
      "search_results" => %{"locations" => search_locations}
    }

    assert {:ok, adapted} = LegacyBoardAdapter.adapt(legacy)
    assert adapted["board_id"] == "dcoa_classic"
    refute Map.has_key?(adapted, "locations")
    assert Enum.map(adapted["suspects"], & &1["location_id"]) == @canonical_ids

    assert adapted["search_results"]["locations"] |> Map.keys() |> Enum.sort() ==
             Enum.sort(@canonical_ids)
  end

  test "does not guess a custom inline board that resembles the legacy seed" do
    [first | rest] = legacy_seed_locations()
    custom = %{"locations" => [Map.put(first, "x", 0.31) | rest]}

    assert {:error, :unknown_board} = LegacyBoardAdapter.adapt(custom)
  end

  defp location(id, name, type, district_ids, x, y) do
    %{
      "id" => id,
      "name" => name,
      "type" => type,
      "district_ids" => district_ids,
      "x" => x,
      "y" => y
    }
  end

  defp legacy_seed_locations do
    [
      location("central-precinct", "Central Precinct", "police_station", ["civic"], 0.3, 0.42),
      location("meridian-array", "Meridian Array", "standard", ["observatory"], 0.42, 0.23),
      location(
        "northlight-boarding-house",
        "Northlight Boarding House",
        "standard",
        ["observatory", "civic"],
        0.39,
        0.34
      ),
      location("city-archive", "City Archive", "standard", ["civic"], 0.35, 0.5),
      location(
        "telegraph-exchange",
        "Telegraph Exchange",
        "standard",
        ["civic", "harbor"],
        0.55,
        0.55
      ),
      location(
        "harbor-precinct",
        "Harbor Precinct",
        "police_station",
        ["harbor"],
        0.68,
        0.61
      ),
      location("breakwater-relay", "Breakwater Relay", "standard", ["harbor"], 0.79, 0.71),
      location(
        "mariner-social-club",
        "Mariner Social Club",
        "mob_joint",
        ["harbor"],
        0.65,
        0.72
      )
    ]
  end
end
