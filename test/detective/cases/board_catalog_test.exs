defmodule Detective.Cases.BoardCatalogTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.BoardCatalog

  @district_ids ~w(westside hollywood central_la san_gabriel_valley south_bay)
  @location_fields ~w(id number slug name type district_ids x y)

  test "Classic catalog contains every numbered board location once" do
    assert {:ok, board} = BoardCatalog.fetch("dcoa_classic")
    locations = board["locations"]
    numbers = Enum.map(locations, & &1["number"])

    assert board["district_ids"] == @district_ids
    assert length(locations) == 100
    assert Enum.sort(numbers) == Enum.to_list(1..100)
    assert Enum.uniq(numbers) == numbers
    assert Enum.map(locations, & &1["id"]) == Enum.map(1..100, &Integer.to_string/1)
  end

  test "locations carry unique canonical names, slugs, types, districts, and coordinates" do
    assert {:ok, locations} = BoardCatalog.locations("dcoa_classic")
    slugs = Enum.map(locations, & &1["slug"])

    assert Enum.uniq(slugs) == slugs

    assert Enum.all?(locations, fn location ->
             Enum.sort(Map.keys(location)) == Enum.sort(@location_fields) and
               location["id"] == Integer.to_string(location["number"]) and
               is_binary(location["name"]) and location["name"] != "" and
               Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, location["slug"]) and
               location["type"] in ~w(standard police_station mob_joint) and
               location["district_ids"] != [] and
               Enum.all?(location["district_ids"], &(&1 in @district_ids)) and
               is_number(location["x"]) and location["x"] >= 0.0 and location["x"] <= 1.0 and
               is_number(location["y"]) and location["y"] >= 0.0 and location["y"] <= 1.0
           end)
  end

  test "special locations match the blue stations and orange mob joints" do
    assert {:ok, locations} = BoardCatalog.locations("dcoa_classic")

    assert location_numbers(locations, "police_station") == [4, 12, 27, 36, 51, 63, 72, 84, 95]
    assert location_numbers(locations, "mob_joint") == [9, 22, 34, 52, 71, 76, 96]

    assert {:ok, headquarters} = BoardCatalog.location("dcoa_classic", "51")
    assert headquarters["name"] == "L.A. Police Department Headquarters"
    assert headquarters["district_ids"] == ["central_la"]
  end

  test "district-border locations bridge every district shown by the planner" do
    assert_location("8", "Beverly Hills Hotel", ~w(westside hollywood))
    assert_location("17", "Country Club Manor", ~w(westside hollywood))
    assert_location("19", "Loyola High", ~w(westside central_la))
    assert_location("20", "McCarty Memorial Christian", ~w(westside))
    assert_location("22", "The Stag & Bull", ~w(westside central_la))
    assert_location("23", "Inglewood Cemetery", ~w(westside south_bay))
    assert_location("33", "Sunset Revue", ~w(hollywood))
    assert_location("38", "Hoover & Temple", ~w(hollywood central_la))
    assert_location("39", "Vermont & Pico", ~w(central_la))
    assert_location("45", "L.A. Times", ~w(hollywood central_la))
    assert_location("53", "Mission & Valley", ~w(central_la san_gabriel_valley))
    assert_location("58", "Occidental College", ~w(hollywood san_gabriel_valley))
    assert_location("59", "Sycamore Park", ~w(hollywood san_gabriel_valley))
    assert_location("82", "Vermont & Manchester", ~w(central_la south_bay))
    assert_location("91", "San Pedro & Manchester", ~w(central_la south_bay))
    assert_location("96", "Topsy's Nightclub", ~w(central_la south_bay))

    assert_location(
      "98",
      "Atlantic & Firestone",
      ~w(central_la san_gabriel_valley south_bay)
    )
  end

  test "marker centers use the complete 1000 by 636 board-image plane" do
    assert {:ok, university} = BoardCatalog.location("dcoa_classic", "1")
    assert university["x"] == 0.127
    assert university["y"] == 0.4151

    assert {:ok, headquarters} = BoardCatalog.location("dcoa_classic", "51")
    assert headquarters["x"] == 0.623
    assert headquarters["y"] == 0.5527

    assert {:ok, anaheim_street} = BoardCatalog.location("dcoa_classic", "100")
    assert anaheim_street["x"] == 0.65
    assert anaheim_street["y"] == 0.8978
  end

  test "unknown board and location IDs return domain errors" do
    assert {:error, :unknown_board} = BoardCatalog.fetch("unknown")
    assert {:error, :unknown_board} = BoardCatalog.locations("unknown")
    assert {:error, :unknown_location} = BoardCatalog.location("dcoa_classic", "101")
    assert {:error, :unknown_location} = BoardCatalog.location("dcoa_classic", 51)
  end

  defp location_numbers(locations, type) do
    locations
    |> Enum.filter(&(&1["type"] == type))
    |> Enum.map(& &1["number"])
  end

  defp assert_location(id, name, district_ids) do
    assert {:ok, location} = BoardCatalog.location("dcoa_classic", id)
    assert location["name"] == name
    assert location["district_ids"] == district_ids
  end
end
