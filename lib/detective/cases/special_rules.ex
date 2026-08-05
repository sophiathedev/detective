defmodule Detective.Cases.SpecialRules do
  @moduledoc """
  Validates and exposes the finite special-rule vocabulary supported by the
  authoritative game engine.

  Case text may describe a rule, but only allow-listed effects can alter state.
  This prevents a browser or an unvalidated case payload from inventing game
  mechanics.
  """

  @detective_counts ~w(2 3 4)
  @visibilities ~w(public chisel)

  alias Detective.Cases.BoardCatalog

  def validate(case_definition) when is_map(case_definition) do
    with {:ok, locations} <- BoardCatalog.locations(case_definition["board_id"]) do
      validate(case_definition, locations)
    else
      _error -> {:error, :invalid_special_rules}
    end
  end

  def validate(_case_definition), do: {:error, :invalid_special_rules}

  def validate(case_definition, locations)
      when is_map(case_definition) and is_list(locations) do
    rules = case_definition["special_rules"] || []

    with true <- is_list(rules),
         true <- unique_rule_ids?(rules),
         true <- Enum.all?(rules, &valid_rule?(&1, case_definition, locations)),
         true <- unique_setup_effects?(rules) do
      :ok
    else
      _invalid -> {:error, :invalid_special_rules}
    end
  end

  def validate(_case_definition, _locations), do: {:error, :invalid_special_rules}

  def starting_days(case_definition, detective_count, default_days) do
    case Enum.find(rules(case_definition), &(effect_type(&1) == "starting_days")) do
      nil -> default_days
      rule -> get_in(rule, ["effect", "days_by_detective_count", to_string(detective_count)])
    end
  end

  def day_rules(case_definition, day) do
    Enum.filter(rules(case_definition), fn rule ->
      rule["trigger"] == "day_started" and get_in(rule, ["effect", "day"]) == day
    end)
  end

  def public_rules(case_definition, triggered_rule_ids \\ []) do
    triggered_rule_ids = MapSet.new(triggered_rule_ids)

    case_definition
    |> rules()
    |> Enum.filter(fn rule ->
      rule["visibility"] == "public" or MapSet.member?(triggered_rule_ids, rule["id"])
    end)
    |> Enum.map(fn rule ->
      triggered? = rule["trigger"] == "setup" or MapSet.member?(triggered_rule_ids, rule["id"])

      %{
        id: rule["id"],
        title: rule["title"],
        text: rule["text"],
        trigger: rule["trigger"],
        triggered: triggered?
      }
    end)
  end

  def chisel_rules(case_definition), do: rules(case_definition)

  defp rules(case_definition) when is_map(case_definition) do
    case case_definition["special_rules"] do
      rules when is_list(rules) -> rules
      _missing -> []
    end
  end

  defp valid_rule?(rule, case_definition, locations) when is_map(rule) do
    is_binary(rule["id"]) and rule["id"] != "" and
      is_binary(rule["title"]) and rule["title"] != "" and
      is_binary(rule["text"]) and rule["text"] != "" and
      rule["visibility"] in @visibilities and valid_effect?(rule, case_definition, locations)
  end

  defp valid_rule?(_rule, _case_definition, _locations), do: false

  defp valid_effect?(
         %{
           "visibility" => "public",
           "trigger" => "setup",
           "effect" => %{
             "type" => "starting_days",
             "days_by_detective_count" => days
           }
         },
         _case_definition,
         _locations
       ) do
    is_map(days) and Enum.sort(Map.keys(days)) == @detective_counts and
      Enum.all?(days, fn {_count, value} -> positive_integer?(value) end)
  end

  defp valid_effect?(
         %{
           "trigger" => "day_started",
           "effect" => %{"type" => "day_reveal", "day" => day} = effect
         },
         case_definition,
         locations
       ) do
    case_card_ids = effect["reveal_case_card_ids"] || []
    suspect_ids = effect["reveal_suspect_ids"] || []
    actor_updates = effect["special_actor_updates"] || []
    valid_case_card_ids = case_definition |> Map.get("case_cards", []) |> ids()
    valid_suspect_ids = case_definition |> Map.get("suspects", []) |> ids()
    valid_actor_ids = case_definition |> Map.get("special_actors", []) |> ids()
    valid_location_ids = ids(locations)

    positive_integer?(day) and day > 1 and day <= minimum_starting_days(case_definition) and
      valid_id_list?(case_card_ids) and valid_id_list?(suspect_ids) and
      valid_actor_updates?(actor_updates, valid_actor_ids, valid_location_ids) and
      (case_card_ids ++ suspect_ids != [] or actor_updates != []) and
      MapSet.subset?(MapSet.new(case_card_ids), valid_case_card_ids) and
      MapSet.subset?(MapSet.new(suspect_ids), valid_suspect_ids)
  end

  defp valid_effect?(_rule, _case_definition, _locations), do: false

  defp valid_actor_updates?(updates, actor_ids, location_ids) when is_list(updates) do
    update_actor_ids = Enum.map(updates, fn update -> is_map(update) && update["actor_id"] end)

    Enum.uniq(update_actor_ids) == update_actor_ids and
      Enum.all?(updates, fn
        update when is_map(update) ->
          keys = update |> Map.keys() |> Enum.sort()
          location_id = update["location_id"]

          keys in [
            ["active", "actor_id", "visible"],
            ["active", "actor_id", "location_id", "visible"]
          ] and MapSet.member?(actor_ids, update["actor_id"]) and update["visible"] == true and
            is_boolean(update["active"]) and
            (is_nil(location_id) or MapSet.member?(location_ids, location_id))

        _update ->
          false
      end)
  end

  defp valid_actor_updates?(_updates, _actor_ids, _location_ids), do: false

  defp unique_rule_ids?(rules) do
    ids = Enum.map(rules, fn rule -> is_map(rule) && rule["id"] end)
    Enum.uniq(ids) == ids
  end

  defp unique_setup_effects?(rules) do
    rules
    |> Enum.count(&(effect_type(&1) == "starting_days"))
    |> Kernel.<=(1)
  end

  defp effect_type(rule) when is_map(rule), do: get_in(rule, ["effect", "type"])
  defp effect_type(_rule), do: nil

  defp minimum_starting_days(case_definition) do
    case Enum.find(rules(case_definition), &(effect_type(&1) == "starting_days")) do
      %{"effect" => %{"days_by_detective_count" => days}} when is_map(days) ->
        days
        |> Map.values()
        |> Enum.filter(&positive_integer?/1)
        |> case do
          [] -> default_minimum_days(case_definition)
          values -> Enum.min(values)
        end

      _missing ->
        default_minimum_days(case_definition)
    end
  end

  defp default_minimum_days(case_definition) do
    case case_definition["max_days"] do
      days when is_integer(days) and days > 0 -> days
      _default -> 7
    end
  end

  defp valid_id_list?(ids) when is_list(ids) do
    Enum.all?(ids, &(is_binary(&1) and &1 != "")) and Enum.uniq(ids) == ids
  end

  defp valid_id_list?(_ids), do: false

  defp ids(entries) when is_list(entries) do
    entries
    |> Enum.reduce_while(MapSet.new(), fn
      %{"id" => id}, ids when is_binary(id) and id != "" ->
        {:cont, MapSet.put(ids, id)}

      _entry, _ids ->
        {:halt, MapSet.new()}
    end)
  end

  defp ids(_entries), do: MapSet.new()

  defp positive_integer?(value), do: is_integer(value) and value > 0
end
