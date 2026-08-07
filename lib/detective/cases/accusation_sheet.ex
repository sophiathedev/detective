defmodule Detective.Cases.AccusationSheet do
  @moduledoc """
  Validates the finite, server-owned accusation vocabulary for a case.

  The browser submits only option IDs. Labels, discovery requirements, and the
  solution remain authoritative case data.
  """

  def validate(case_definition) when is_map(case_definition) do
    options = case_definition["accusation_options"]
    solution = case_definition["solution"]

    cond do
      is_nil(options) ->
        :ok

      not is_map(options) or not is_map(solution) ->
        {:error, :invalid_accusation_options}

      true ->
        validate_options(case_definition, options, solution)
    end
  end

  def validate(_case_definition), do: {:error, :invalid_accusation_options}

  def configured?(case_definition), do: is_map(case_definition["accusation_options"])

  def options(case_definition) do
    case case_definition["accusation_options"] do
      %{"weapons" => weapons, "motives" => motives}
      when is_list(weapons) and is_list(motives) ->
        {:ok, %{weapons: weapons, motives: motives}}

      _invalid ->
        {:error, :accusation_not_available}
    end
  end

  def solution(case_definition) do
    case case_definition["solution"] do
      %{
        "suspect_id" => suspect_id,
        "weapon_id" => weapon_id,
        "motive_id" => motive_id
      }
      when is_binary(suspect_id) and is_binary(weapon_id) and is_binary(motive_id) ->
        {:ok, %{"suspect_id" => suspect_id, "weapon_id" => weapon_id, "motive_id" => motive_id}}

      _invalid ->
        {:error, :accusation_not_available}
    end
  end

  def build_guess(case_definition, payload) when is_map(payload) do
    with {:ok, %{weapons: weapons, motives: motives}} <- options(case_definition),
         suspect_id when is_binary(suspect_id) <- payload["suspect_id"],
         weapon_id when is_binary(weapon_id) <- payload["weapon_id"],
         motive_id when is_binary(motive_id) <- payload["motive_id"],
         true <- suspect_id in suspect_ids(case_definition),
         true <- Enum.any?(weapons, &(&1["id"] == weapon_id)),
         true <- Enum.any?(motives, &(&1["id"] == motive_id)) do
      {:ok, %{"suspect_id" => suspect_id, "weapon_id" => weapon_id, "motive_id" => motive_id}}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_accusation}
    end
  end

  def build_guess(_case_definition, _payload), do: {:error, :invalid_accusation}

  def weapon(case_definition, weapon_id) do
    with {:ok, %{weapons: weapons}} <- options(case_definition),
         weapon when not is_nil(weapon) <- Enum.find(weapons, &(&1["id"] == weapon_id)) do
      {:ok, weapon}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :invalid_accusation}
    end
  end

  def correct_count(case_definition, guess) do
    with {:ok, solution} <- solution(case_definition) do
      count =
        ~w(suspect_id weapon_id motive_id)
        |> Enum.count(&(guess[&1] == solution[&1]))

      {:ok, count}
    end
  end

  def correct?(case_definition, guess) do
    match?({:ok, 3}, correct_count(case_definition, guess))
  end

  def revealed_solution(case_definition) do
    with {:ok, solution} <- solution(case_definition),
         {:ok, revealed} <- revealed_guess(case_definition, solution) do
      {:ok, Map.delete(revealed, "correct_count")}
    end
  end

  def revealed_guess(case_definition, guess) do
    with {:ok, guess} <- build_guess(case_definition, guess),
         {:ok, %{weapons: weapons, motives: motives}} <- options(case_definition),
         {:ok, correct_count} <- correct_count(case_definition, guess) do
      suspect =
        case_definition
        |> Map.get("suspects", [])
        |> Enum.find(&(&1["id"] == guess["suspect_id"]))

      weapon = Enum.find(weapons, &(&1["id"] == guess["weapon_id"]))
      motive = Enum.find(motives, &(&1["id"] == guess["motive_id"]))

      {:ok,
       Map.merge(guess, %{
         "suspect_name" => suspect["name"],
         "weapon_label" => weapon["label"],
         "motive_label" => motive["label"],
         "correct_count" => correct_count
       })}
    end
  end

  def public_options(case_definition, known_case_card_ids, revealed_suspect_ids) do
    with {:ok, %{weapons: weapons, motives: motives}} <- options(case_definition) do
      suspects =
        case_definition
        |> Map.get("suspects", [])
        |> Enum.filter(&(&1["id"] in revealed_suspect_ids))
        |> Enum.map(&Map.take(&1, ["id", "name"]))

      weapons =
        weapons
        |> Enum.filter(&(&1["case_card_id"] in known_case_card_ids))
        |> Enum.map(&Map.take(&1, ["id", "label", "case_card_id"]))

      motives = Enum.map(motives, &Map.take(&1, ["id", "label"]))
      %{suspects: suspects, weapons: weapons, motives: motives}
    else
      _error -> %{suspects: [], weapons: [], motives: []}
    end
  end

  defp validate_options(case_definition, options, solution) do
    weapons = options["weapons"]
    motives = options["motives"]
    suspect_ids = suspect_ids(case_definition)
    case_card_ids = case_definition |> Map.get("case_cards", []) |> ids()

    with true <- valid_options?(weapons, ~w(id label case_card_id)),
         true <- valid_options?(motives, ~w(id label)),
         true <- Enum.all?(weapons, &(&1["case_card_id"] in case_card_ids)),
         true <- solution["suspect_id"] in suspect_ids,
         true <- Enum.any?(weapons, &(&1["id"] == solution["weapon_id"])),
         true <- Enum.any?(motives, &(&1["id"] == solution["motive_id"])) do
      :ok
    else
      _invalid -> {:error, :invalid_accusation_options}
    end
  end

  defp valid_options?(options, required_keys) when is_list(options) and options != [] do
    ids = Enum.map(options, & &1["id"])

    Enum.all?(options, fn option ->
      is_map(option) and
        Enum.all?(required_keys, fn key ->
          is_binary(option[key]) and option[key] != ""
        end)
    end) and Enum.uniq(ids) == ids
  end

  defp valid_options?(_options, _required_keys), do: false

  defp suspect_ids(case_definition),
    do: case_definition |> Map.get("suspects", []) |> ids()

  defp ids(entries), do: Enum.map(entries, & &1["id"])
end
