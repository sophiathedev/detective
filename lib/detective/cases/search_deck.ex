defmodule Detective.Cases.SearchDeck do
  @moduledoc """
  Validates and resolves server-owned Search cards for a case.

  Search text and reveal instructions never come from a client command.
  """

  alias Detective.Cases.ResponseMatrix

  def validate(case_definition) when is_map(case_definition) do
    case case_definition["search_results"] do
      nil ->
        :ok

      search_results when is_map(search_results) ->
        validate_search_results(case_definition, search_results)

      _invalid ->
        {:error, :invalid_search_results}
    end
  end

  def validate(_case_definition), do: {:error, :invalid_search_results}

  def configured?(case_definition) do
    case_definition
    |> Map.get("search_results")
    |> is_map()
  end

  def location_result(case_definition, location_id) when is_binary(location_id) do
    search_results = case_definition["search_results"] || %{}
    locations = search_results["locations"] || %{}

    result = locations[location_id] || search_results["all_other_locations"]
    normalize_result(result, "location", location_id)
  end

  def location_result(_case_definition, _location_id), do: {:error, :search_not_available}

  def suspect_result(case_definition, suspect_id) when is_binary(suspect_id) do
    search_results = case_definition["search_results"] || %{}
    suspects = search_results["suspects"] || %{}
    normalize_result(suspects[suspect_id], "suspect", suspect_id)
  end

  def suspect_result(_case_definition, _suspect_id), do: {:error, :search_not_available}

  def case_card(case_definition, card_id) do
    case Enum.find(ResponseMatrix.topics(case_definition), &(&1.id == card_id)) do
      nil -> {:error, :invalid_case_card}
      card -> {:ok, card}
    end
  end

  def case_cards(case_definition, card_ids) do
    card_ids
    |> Enum.reduce_while({:ok, []}, fn card_id, {:ok, cards} ->
      case case_card(case_definition, card_id) do
        {:ok, card} -> {:cont, {:ok, [card | cards]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, cards} -> {:ok, Enum.reverse(cards)}
      {:error, reason} -> {:error, reason}
    end
  end

  def target_key(%{target_type: target_type, target_id: target_id}),
    do: "#{target_type}:#{target_id}"

  defp validate_search_results(case_definition, search_results) do
    locations = search_results["locations"] || %{}
    suspects = search_results["suspects"] || %{}
    fallback = search_results["all_other_locations"]

    location_ids = case_definition |> Map.get("locations", []) |> ids()
    suspect_ids = case_definition |> Map.get("suspects", []) |> ids()
    card_ids = case_definition |> Map.get("case_cards", []) |> ids()

    with true <- is_map(locations),
         true <- is_map(suspects),
         true <- map_keys_within?(locations, location_ids),
         true <- map_keys_within?(suspects, suspect_ids),
         true <- Enum.all?(suspect_ids, &Map.has_key?(suspects, &1)),
         :ok <- validate_result(fallback, card_ids, suspect_ids),
         :ok <- validate_results(Map.values(locations), card_ids, suspect_ids),
         :ok <- validate_results(Map.values(suspects), card_ids, suspect_ids) do
      :ok
    else
      _invalid -> {:error, :invalid_search_results}
    end
  end

  defp validate_results(results, card_ids, suspect_ids) do
    if Enum.all?(results, &(validate_result(&1, card_ids, suspect_ids) == :ok)) do
      :ok
    else
      {:error, :invalid_search_results}
    end
  end

  defp validate_result(result, card_ids, suspect_ids) when is_map(result) do
    reveal_ids = result["reveal_case_card_ids"] || []
    take_ids = result["take_case_card_ids"] || []
    reveal_suspect_ids = result["reveal_suspect_ids"] || []

    cond do
      not (is_binary(result["text"]) and result["text"] != "") ->
        {:error, :invalid_search_result}

      not is_boolean(result["archive"]) ->
        {:error, :invalid_search_result}

      not id_list?(reveal_ids) or not id_list?(take_ids) or not id_list?(reveal_suspect_ids) ->
        {:error, :invalid_search_result}

      not MapSet.subset?(MapSet.new(reveal_ids), card_ids) ->
        {:error, :invalid_search_reference}

      not MapSet.subset?(MapSet.new(take_ids), MapSet.new(reveal_ids)) ->
        {:error, :invalid_search_reference}

      not MapSet.subset?(MapSet.new(reveal_suspect_ids), suspect_ids) ->
        {:error, :invalid_search_reference}

      length(reveal_suspect_ids) > 1 ->
        {:error, :invalid_search_result}

      true ->
        :ok
    end
  end

  defp validate_result(_result, _card_ids, _suspect_ids), do: {:error, :invalid_search_result}

  defp normalize_result(result, target_type, target_id) when is_map(result) do
    {:ok,
     %{
       target_type: target_type,
       target_id: target_id,
       text: result["text"],
       archive: result["archive"],
       reveal_case_card_ids: result["reveal_case_card_ids"] || [],
       take_case_card_ids: result["take_case_card_ids"] || [],
       reveal_suspect_ids: result["reveal_suspect_ids"] || []
     }}
  end

  defp normalize_result(_result, _target_type, _target_id),
    do: {:error, :search_not_available}

  defp ids(entries) do
    entries
    |> Enum.map(& &1["id"])
    |> MapSet.new()
  end

  defp map_keys_within?(map, allowed_ids) do
    map
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.subset?(allowed_ids)
  end

  defp id_list?(ids),
    do: is_list(ids) and Enum.all?(ids, &(is_binary(&1) and &1 != "")) and Enum.uniq(ids) == ids
end
