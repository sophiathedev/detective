defmodule Detective.Cases.LegacyBoardAdapter do
  @moduledoc """
  Adapts exact, known pre-catalog case definitions at their consumption boundary.

  Published case versions remain immutable. Only the historical test fixture
  topology and the version 5 sample seed topology are recognized.
  """

  @fixture_v1_locations [
    %{
      "id" => "central-precinct",
      "name" => "Central Precinct",
      "type" => "police_station",
      "district_ids" => ["central"],
      "x" => 0.25,
      "y" => 0.35
    },
    %{
      "id" => "canal-gate",
      "name" => "Canal Gate",
      "type" => "standard",
      "district_ids" => ["central", "harbor"],
      "x" => 0.5,
      "y" => 0.5
    },
    %{
      "id" => "pier-club",
      "name" => "Pier Club",
      "type" => "mob_joint",
      "district_ids" => ["harbor"],
      "x" => 0.75,
      "y" => 0.7
    }
  ]

  @fixture_v1_id_map %{
    "central-precinct" => "51",
    "canal-gate" => "82",
    "pier-club" => "96"
  }

  @seed_v5_locations [
    %{
      "id" => "central-precinct",
      "name" => "Central Precinct",
      "type" => "police_station",
      "district_ids" => ["civic"],
      "x" => 0.3,
      "y" => 0.42
    },
    %{
      "id" => "meridian-array",
      "name" => "Meridian Array",
      "type" => "standard",
      "district_ids" => ["observatory"],
      "x" => 0.42,
      "y" => 0.23
    },
    %{
      "id" => "northlight-boarding-house",
      "name" => "Northlight Boarding House",
      "type" => "standard",
      "district_ids" => ["observatory", "civic"],
      "x" => 0.39,
      "y" => 0.34
    },
    %{
      "id" => "city-archive",
      "name" => "City Archive",
      "type" => "standard",
      "district_ids" => ["civic"],
      "x" => 0.35,
      "y" => 0.5
    },
    %{
      "id" => "telegraph-exchange",
      "name" => "Telegraph Exchange",
      "type" => "standard",
      "district_ids" => ["civic", "harbor"],
      "x" => 0.55,
      "y" => 0.55
    },
    %{
      "id" => "harbor-precinct",
      "name" => "Harbor Precinct",
      "type" => "police_station",
      "district_ids" => ["harbor"],
      "x" => 0.68,
      "y" => 0.61
    },
    %{
      "id" => "breakwater-relay",
      "name" => "Breakwater Relay",
      "type" => "standard",
      "district_ids" => ["harbor"],
      "x" => 0.79,
      "y" => 0.71
    },
    %{
      "id" => "mariner-social-club",
      "name" => "Mariner Social Club",
      "type" => "mob_joint",
      "district_ids" => ["harbor"],
      "x" => 0.65,
      "y" => 0.72
    }
  ]

  @seed_v5_id_map %{
    "central-precinct" => "51",
    "meridian-array" => "29",
    "northlight-boarding-house" => "38",
    "city-archive" => "48",
    "telegraph-exchange" => "82",
    "harbor-precinct" => "84",
    "breakwater-relay" => "99",
    "mariner-social-club" => "96"
  }

  @legacy_adapters [
    {@fixture_v1_locations, @fixture_v1_id_map},
    {@seed_v5_locations, @seed_v5_id_map}
  ]

  def adapt(%{"board_id" => _board_id} = case_definition), do: {:ok, case_definition}

  def adapt(%{"locations" => locations} = case_definition) when is_list(locations) do
    case Enum.find(@legacy_adapters, fn {known_locations, _id_map} ->
           locations == known_locations
         end) do
      {_known_locations, id_map} -> {:ok, rewrite(case_definition, id_map)}
      nil -> {:error, :unknown_board}
    end
  end

  def adapt(_case_definition), do: {:error, :unknown_board}

  defp rewrite(case_definition, id_map) do
    case_definition
    |> Map.delete("locations")
    |> Map.put("board_id", "dcoa_classic")
    |> Map.update("suspects", nil, &rewrite_suspects(&1, id_map))
    |> Map.update("search_results", nil, &rewrite_search_results(&1, id_map))
  end

  defp rewrite_suspects(suspects, id_map) when is_list(suspects) do
    Enum.map(suspects, fn
      %{"location_id" => location_id} = suspect ->
        Map.put(suspect, "location_id", Map.get(id_map, location_id, location_id))

      suspect ->
        suspect
    end)
  end

  defp rewrite_suspects(suspects, _id_map), do: suspects

  defp rewrite_search_results(search_results, id_map) when is_map(search_results) do
    Map.update(search_results, "locations", nil, fn
      locations when is_map(locations) ->
        Map.new(locations, fn {location_id, result} ->
          {Map.get(id_map, location_id, location_id), result}
        end)

      locations ->
        locations
    end)
  end

  defp rewrite_search_results(search_results, _id_map), do: search_results
end
