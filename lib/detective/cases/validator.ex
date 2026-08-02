defmodule Detective.Cases.Validator do
  @moduledoc """
  Validates the structural rules required by the authoritative engine.
  """

  @location_types ~w(standard police_station mob_joint)

  alias Detective.Cases.ResponseMatrix

  def validate(case_definition) when is_map(case_definition) do
    locations = case_definition["locations"]

    with :ok <- validate_locations(locations),
         :ok <- validate_unique_location_ids(locations),
         :ok <- validate_police_station(locations),
         :ok <- validate_three_move_reachability(locations),
         :ok <- validate_suspect_locations(case_definition["suspects"], locations),
         :ok <- ResponseMatrix.validate(case_definition) do
      :ok
    end
  end

  def validate(_case_definition), do: {:error, :invalid_case_definition}

  defp validate_locations(locations) when is_list(locations) and locations != [] do
    if Enum.all?(locations, &valid_location?/1) do
      :ok
    else
      {:error, :invalid_locations}
    end
  end

  defp validate_locations(_locations), do: {:error, :invalid_locations}

  defp valid_location?(location) do
    is_map(location) and is_binary(location["id"]) and is_binary(location["name"]) and
      location["type"] in @location_types and
      is_list(location["district_ids"]) and location["district_ids"] != [] and
      Enum.all?(location["district_ids"], &is_binary/1) and valid_coordinate?(location["x"]) and
      valid_coordinate?(location["y"])
  end

  defp valid_coordinate?(value), do: is_number(value) and value >= 0 and value <= 1

  defp validate_unique_location_ids(locations) do
    ids = Enum.map(locations, & &1["id"])

    if Enum.uniq(ids) == ids do
      :ok
    else
      {:error, :duplicate_location_id}
    end
  end

  defp validate_police_station(locations) do
    if Enum.any?(locations, &(&1["type"] == "police_station")) do
      :ok
    else
      {:error, :police_station_required}
    end
  end

  defp validate_three_move_reachability(locations) do
    graph = movement_graph(locations)
    all_ids = graph |> Map.keys() |> MapSet.new()

    if Enum.all?(Map.keys(graph), fn source_id ->
         reachable_within(graph, MapSet.new([source_id]), MapSet.new([source_id]), 3) == all_ids
       end) do
      :ok
    else
      {:error, :location_beyond_three_moves}
    end
  end

  defp movement_graph(locations) do
    Map.new(locations, fn location ->
      neighbours =
        locations
        |> Enum.reject(&(&1["id"] == location["id"]))
        |> Enum.filter(&same_district?(location, &1))
        |> Enum.map(& &1["id"])

      {location["id"], neighbours}
    end)
  end

  defp reachable_within(_graph, visited, _frontier, 0), do: visited

  defp reachable_within(graph, visited, frontier, moves_left) do
    if MapSet.size(frontier) == 0 do
      visited
    else
      next_frontier =
        frontier
        |> Enum.flat_map(&Map.fetch!(graph, &1))
        |> MapSet.new()
        |> MapSet.difference(visited)

      reachable_within(
        graph,
        MapSet.union(visited, next_frontier),
        next_frontier,
        moves_left - 1
      )
    end
  end

  defp same_district?(location_a, location_b) do
    location_a["district_ids"]
    |> MapSet.new()
    |> MapSet.disjoint?(MapSet.new(location_b["district_ids"]))
    |> Kernel.not()
  end

  defp validate_suspect_locations(nil, _locations), do: :ok

  defp validate_suspect_locations(suspects, locations) when is_list(suspects) do
    location_ids = locations |> Enum.map(& &1["id"]) |> MapSet.new()

    if Enum.all?(suspects, fn suspect ->
         is_map(suspect) and is_binary(suspect["id"]) and
           MapSet.member?(location_ids, suspect["location_id"])
       end) do
      :ok
    else
      {:error, :invalid_suspect_location}
    end
  end

  defp validate_suspect_locations(_suspects, _locations),
    do: {:error, :invalid_suspects}
end
