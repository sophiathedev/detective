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
      {_known_locations, id_map} -> rewrite(case_definition, id_map)
      nil -> {:error, :unknown_board}
    end
  end

  def adapt(_case_definition), do: {:error, :unknown_board}

  defp rewrite(case_definition, id_map) do
    with {:ok, suspects} <- rewrite_suspects(case_definition["suspects"], id_map),
         {:ok, search_results} <-
           rewrite_search_results(case_definition["search_results"], id_map) do
      {:ok,
       case_definition
       |> Map.delete("locations")
       |> Map.put("board_id", "dcoa_classic")
       |> Map.put("suspects", suspects)
       |> Map.put("search_results", search_results)}
    end
  end

  defp rewrite_suspects(nil, _id_map), do: {:ok, nil}

  defp rewrite_suspects(suspects, id_map) when is_list(suspects) do
    Enum.reduce_while(suspects, {:ok, []}, fn
      %{"location_id" => location_id} = suspect, {:ok, rewritten} ->
        case Map.fetch(id_map, location_id) do
          {:ok, canonical_id} ->
            {:cont, {:ok, [Map.put(suspect, "location_id", canonical_id) | rewritten]}}

          :error ->
            {:halt, {:error, :invalid_suspect_location}}
        end

      _suspect, _rewritten ->
        {:halt, {:error, :invalid_suspect_location}}
    end)
    |> case do
      {:ok, rewritten} -> {:ok, Enum.reverse(rewritten)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rewrite_suspects(suspects, _id_map), do: {:ok, suspects}

  defp rewrite_search_results(nil, _id_map), do: {:ok, nil}

  defp rewrite_search_results(search_results, id_map) when is_map(search_results) do
    with {:ok, locations} <- rewrite_search_locations(search_results["locations"], id_map) do
      {:ok, Map.put(search_results, "locations", locations)}
    end
  end

  defp rewrite_search_results(search_results, _id_map), do: {:ok, search_results}

  defp rewrite_search_locations(nil, _id_map), do: {:ok, nil}

  defp rewrite_search_locations(locations, id_map) when is_map(locations) do
    Enum.reduce_while(locations, {:ok, %{}}, fn {location_id, result}, {:ok, rewritten} ->
      with {:ok, canonical_id} <- Map.fetch(id_map, location_id),
           false <- Map.has_key?(rewritten, canonical_id) do
        {:cont, {:ok, Map.put(rewritten, canonical_id, result)}}
      else
        _invalid -> {:halt, {:error, :invalid_search_results}}
      end
    end)
  end

  defp rewrite_search_locations(locations, _id_map), do: {:ok, locations}
end
