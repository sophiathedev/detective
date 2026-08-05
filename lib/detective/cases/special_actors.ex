defmodule Detective.Cases.SpecialActors do
  @moduledoc """
  Validates case-owned map actors and exposes their finite interaction surface.

  Actor effects remain server-only. Public and Detective projections receive
  only the identity, position, costs, and labels needed to render legal choices.
  """

  @kinds ~w(counter_surveillance contact witness)
  @blocked_actions ~w(search_location search_suspect interrogate)
  @effect_types ~w(disable_actor private_case_cards)

  def validate(case_definition, locations) when is_map(case_definition) and is_list(locations) do
    actors = actors(case_definition)
    location_ids = locations |> ids() |> MapSet.new()
    case_card_ids = case_definition |> Map.get("case_cards", []) |> ids() |> MapSet.new()

    with true <- unique_ids?(actors),
         true <- Enum.all?(actors, &valid_actor?(&1, location_ids, case_card_ids)) do
      :ok
    else
      _invalid -> {:error, :invalid_special_actors}
    end
  end

  def validate(_case_definition, _locations), do: {:error, :invalid_special_actors}

  def initialize(case_definition) do
    case_definition
    |> actors()
    |> Map.new(fn actor ->
      {actor["id"],
       %{
         id: actor["id"],
         name: actor["name"],
         role: actor["role"],
         kind: actor["kind"],
         location_id: actor["location_id"],
         active: true,
         blocks: actor["blocks"] || [],
         options: Enum.map(actor["options"], &normalize_option/1),
         used_option_ids: []
       }}
    end)
  end

  def public_actors(runtime_actors) when is_map(runtime_actors) do
    runtime_actors
    |> Map.values()
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn actor ->
      %{
        id: actor.id,
        name: actor.name,
        role: actor.role,
        kind: actor.kind,
        location_id: actor.location_id,
        active: actor.active,
        blocks: if(actor.active, do: actor.blocks, else: [])
      }
    end)
  end

  def available_interactions(runtime_actors, %{location_id: location_id} = player)
      when is_map(runtime_actors) and is_binary(location_id) do
    runtime_actors
    |> Map.values()
    |> Enum.filter(&(&1.active and &1.location_id == location_id))
    |> Enum.map(fn actor ->
      options =
        actor.options
        |> Enum.filter(&option_available?(&1, actor, player))
        |> Enum.map(&public_option/1)

      %{
        actor_id: actor.id,
        name: actor.name,
        role: actor.role,
        kind: actor.kind,
        location_id: actor.location_id,
        options: options
      }
    end)
    |> Enum.reject(&(&1.options == []))
    |> Enum.sort_by(& &1.name)
  end

  def available_interactions(_runtime_actors, _player), do: []

  def fetch_option(runtime_actors, actor_id, option_id)
      when is_map(runtime_actors) and is_binary(actor_id) and is_binary(option_id) do
    with %{active: true} = actor <- Map.get(runtime_actors, actor_id),
         option when is_map(option) <- Enum.find(actor.options, &(&1.id == option_id)) do
      {:ok, actor, option}
    else
      _missing -> {:error, :invalid_special_interaction}
    end
  end

  def fetch_option(_runtime_actors, _actor_id, _option_id),
    do: {:error, :invalid_special_interaction}

  def option_available?(option, actor, player) do
    (not option.once or option.id not in actor.used_option_ids) and
      player.actions_remaining >= option.action_cost and player.scratch >= option.scratch_cost
  end

  def blocks_action?(runtime_actors, location_id, action)
      when is_map(runtime_actors) and is_binary(location_id) and is_binary(action) do
    Enum.any?(runtime_actors, fn {_id, actor} ->
      actor.active and actor.location_id == location_id and action in actor.blocks
    end)
  end

  def blocks_action?(_runtime_actors, _location_id, _action), do: false

  def mark_used(runtime_actors, actor_id, option) do
    Map.update!(runtime_actors, actor_id, fn actor ->
      actor =
        if option.once do
          %{actor | used_option_ids: Enum.uniq([option.id | actor.used_option_ids])}
        else
          actor
        end

      if Enum.any?(option.effects, &(&1["type"] == "disable_actor")) do
        %{actor | active: false}
      else
        actor
      end
    end)
  end

  def private_case_card_ids(option) do
    option.effects
    |> Enum.filter(&(&1["type"] == "private_case_cards"))
    |> Enum.flat_map(& &1["case_card_ids"])
    |> Enum.uniq()
  end

  defp actors(case_definition) do
    case case_definition["special_actors"] do
      nil -> []
      actors when is_list(actors) -> actors
      _invalid -> [nil]
    end
  end

  defp valid_actor?(actor, location_ids, case_card_ids) when is_map(actor) do
    blocks = actor["blocks"] || []
    options = actor["options"]

    non_empty_binary?(actor["id"]) and non_empty_binary?(actor["name"]) and
      non_empty_binary?(actor["role"]) and actor["kind"] in @kinds and
      MapSet.member?(location_ids, actor["location_id"]) and valid_blocks?(blocks) and
      (actor["kind"] != "counter_surveillance" or blocks != []) and
      is_list(options) and options != [] and unique_ids?(options) and
      Enum.all?(options, &valid_option?(&1, case_card_ids))
  end

  defp valid_actor?(_actor, _location_ids, _case_card_ids), do: false

  defp valid_option?(option, case_card_ids) when is_map(option) do
    effects = option["effects"]

    non_empty_binary?(option["id"]) and non_empty_binary?(option["label"]) and
      integer_between?(option["action_cost"], 0, 4) and
      non_negative_integer?(option["scratch_cost"]) and is_boolean(option["once"]) and
      is_list(effects) and effects != [] and unique_effect_types?(effects) and
      Enum.all?(effects, &valid_effect?(&1, case_card_ids))
  end

  defp valid_option?(_option, _case_card_ids), do: false

  defp valid_effect?(%{"type" => "disable_actor"} = effect, _case_card_ids),
    do: Map.keys(effect) == ["type"]

  defp valid_effect?(
         %{"type" => "private_case_cards", "case_card_ids" => ids} = effect,
         valid_ids
       ) do
    Enum.sort(Map.keys(effect)) == ["case_card_ids", "type"] and valid_id_list?(ids) and
      MapSet.subset?(MapSet.new(ids), valid_ids)
  end

  defp valid_effect?(_effect, _case_card_ids), do: false

  defp normalize_option(option) do
    %{
      id: option["id"],
      label: option["label"],
      action_cost: option["action_cost"],
      scratch_cost: option["scratch_cost"],
      once: option["once"],
      effects: option["effects"]
    }
  end

  defp public_option(option) do
    Map.take(option, [:id, :label, :action_cost, :scratch_cost])
  end

  defp unique_ids?(entries) when is_list(entries) do
    entry_ids = Enum.map(entries, fn entry -> is_map(entry) && entry["id"] end)
    Enum.uniq(entry_ids) == entry_ids
  end

  defp unique_effect_types?(effects) do
    types = Enum.map(effects, fn effect -> is_map(effect) && effect["type"] end)
    Enum.all?(types, &(&1 in @effect_types)) and Enum.uniq(types) == types
  end

  defp valid_blocks?(blocks) when is_list(blocks) do
    Enum.all?(blocks, &(&1 in @blocked_actions)) and Enum.uniq(blocks) == blocks
  end

  defp valid_blocks?(_blocks), do: false

  defp valid_id_list?(entries) when is_list(entries) and entries != [] do
    Enum.all?(entries, &non_empty_binary?/1) and Enum.uniq(entries) == entries
  end

  defp valid_id_list?(_entries), do: false

  defp ids(entries) when is_list(entries) do
    Enum.flat_map(entries, fn
      %{"id" => id} when is_binary(id) -> [id]
      _entry -> []
    end)
  end

  defp non_empty_binary?(value), do: is_binary(value) and value != ""
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp integer_between?(value, minimum, maximum),
    do: is_integer(value) and value in minimum..maximum
end
