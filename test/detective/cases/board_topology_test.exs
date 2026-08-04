defmodule Detective.Cases.BoardTopologyTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.BoardTopology

  test "rejects a board without a Police Station" do
    locations = Enum.map(connected_locations(), &Map.put(&1, "type", "standard"))

    assert {:error, :police_station_required} = BoardTopology.validate(locations)
  end

  test "rejects a location beyond three district moves" do
    disconnected = [location("remote", "standard", ["remote"]) | connected_locations()]

    assert {:error, :location_beyond_three_moves} = BoardTopology.validate(disconnected)
  end

  test "accepts a structurally valid connected board" do
    assert :ok = BoardTopology.validate(connected_locations())
  end

  defp connected_locations do
    [
      location("precinct", "police_station", ["central"]),
      location("border", "standard", ["central", "harbor"]),
      location("pier", "mob_joint", ["harbor"])
    ]
  end

  defp location(id, type, district_ids) do
    %{
      "id" => id,
      "name" => String.capitalize(id),
      "type" => type,
      "district_ids" => district_ids,
      "x" => 0.5,
      "y" => 0.5
    }
  end
end
