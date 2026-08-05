defmodule Detective.Cases.SpecialActors do
  @moduledoc """
  Validates case-owned map actors and exposes their finite interaction surface.

  Actor effects remain server-only. Public and Detective projections receive
  only the identity, position, costs, and labels needed to render legal choices.
  """

  @kinds ~w(counter_surveillance contact witness)
  @blocked_actions ~w(search_location search_suspect interrogate)
  @effect_types ~w(disable_actor move_actor private_case_cards public_case_cards reveal_suspects)

  def validate(case_definition, locations) when is_map(case_definition) and is_list(locations) do
    actors = actors(case_definition)
    location_ids = locations |> ids() |> MapSet.new()
    case_card_ids = case_definition |> Map.get("case_cards", []) |> ids() |> MapSet.new()
    suspect_ids = case_definition |> Map.get("suspects", []) |> ids() |> MapSet.new()
    valid_ids = %{locations: location_ids, case_cards: case_card_ids, suspects: suspect_ids}

    with true <- unique_ids?(actors),
         true <- Enum.all?(actors, &valid_actor?(&1, valid_ids)) do
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
         visible: Map.get(actor, "initially_visible", true),
         active: Map.get(actor, "initially_active", true),
         interaction_disabled: false,
         blocks: actor["blocks"] || [],
         options: Enum.map(actor["options"], &normalize_option/1),
         used_option_ids: [],
         resolved_choice_groups: []
       }}
    end)
  end

  def public_actors(runtime_actors) when is_map(runtime_actors) do
    runtime_actors
    |> Map.values()
    |> Enum.filter(& &1.visible)
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
    |> Enum.filter(&(&1.visible and &1.active and &1.location_id == location_id))
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
    with %{visible: true, active: true} = actor <- Map.get(runtime_actors, actor_id),
         option when is_map(option) <- Enum.find(actor.options, &(&1.id == option_id)) do
      {:ok, actor, option}
    else
      _missing -> {:error, :invalid_special_interaction}
    end
  end

  def fetch_option(_runtime_actors, _actor_id, _option_id),
    do: {:error, :invalid_special_interaction}

  def option_available?(option, actor, player) do
    choice_group = Map.get(option, :choice_group)

    (not option.once or option.id not in actor.used_option_ids) and
      (is_nil(choice_group) or
         choice_group not in Map.get(actor, :resolved_choice_groups, [])) and
      player.actions_remaining >= option.action_cost and player.scratch >= option.scratch_cost
  end

  def blocks_action?(runtime_actors, location_id, action)
      when is_map(runtime_actors) and is_binary(location_id) and is_binary(action) do
    Enum.any?(runtime_actors, fn {_id, actor} ->
      actor.visible and actor.active and actor.location_id == location_id and
        action in actor.blocks
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

      actor =
        if choice_group = Map.get(option, :choice_group) do
          Map.put(
            actor,
            :resolved_choice_groups,
            Enum.uniq([choice_group | Map.get(actor, :resolved_choice_groups, [])])
          )
        else
          actor
        end

      actor =
        case destination_location_id(option) do
          nil -> actor
          location_id -> %{actor | location_id: location_id}
        end

      if Enum.any?(option.effects, &(&1["type"] == "disable_actor")) do
        %{actor | active: false, interaction_disabled: true}
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

  def public_case_card_ids(option) do
    effect_ids(option, "public_case_cards", "case_card_ids")
  end

  def revealed_suspect_ids(option) do
    effect_ids(option, "reveal_suspects", "suspect_ids")
  end

  def destination_location_id(option) do
    case Enum.find(option.effects, &(&1["type"] == "move_actor")) do
      nil -> nil
      effect -> effect["location_id"]
    end
  end

  def apply_lifecycle_updates(runtime_actors, updates)
      when is_map(runtime_actors) and is_list(updates) do
    Enum.reduce(updates, {runtime_actors, []}, fn update, {actors, public_updates} ->
      actor = Map.fetch!(actors, update["actor_id"])
      requested_active = update["active"]

      next_actor = %{
        actor
        | visible: true,
          active: requested_active and not actor.interaction_disabled,
          location_id: update["location_id"] || actor.location_id
      }

      public_update = %{
        id: actor.id,
        name: actor.name,
        revealed: not actor.visible,
        active: next_actor.active,
        from_location_id: actor.location_id,
        location_id: next_actor.location_id
      }

      {Map.put(actors, actor.id, next_actor), public_updates ++ [public_update]}
    end)
  end

  defp actors(case_definition) do
    case case_definition["special_actors"] do
      nil -> []
      actors when is_list(actors) -> actors
      _invalid -> [nil]
    end
  end

  defp valid_actor?(actor, valid_ids) when is_map(actor) do
    blocks = actor["blocks"] || []
    options = actor["options"]
    initially_visible = Map.get(actor, "initially_visible", true)
    initially_active = Map.get(actor, "initially_active", true)

    non_empty_binary?(actor["id"]) and non_empty_binary?(actor["name"]) and
      non_empty_binary?(actor["role"]) and actor["kind"] in @kinds and
      MapSet.member?(valid_ids.locations, actor["location_id"]) and valid_blocks?(blocks) and
      is_boolean(initially_visible) and is_boolean(initially_active) and
      (not initially_active or initially_visible) and
      (actor["kind"] != "counter_surveillance" or blocks != []) and
      is_list(options) and options != [] and unique_ids?(options) and
      valid_choice_groups?(options) and Enum.all?(options, &valid_option?(&1, valid_ids))
  end

  defp valid_actor?(_actor, _valid_ids), do: false

  defp valid_option?(option, valid_ids) when is_map(option) do
    effects = option["effects"]
    choice_group = option["choice_group"]

    non_empty_binary?(option["id"]) and non_empty_binary?(option["label"]) and
      integer_between?(option["action_cost"], 0, 4) and
      non_negative_integer?(option["scratch_cost"]) and is_boolean(option["once"]) and
      (is_nil(choice_group) or non_empty_binary?(choice_group)) and
      is_list(effects) and effects != [] and unique_effect_types?(effects) and
      Enum.all?(effects, &valid_effect?(&1, valid_ids)) and
      disjoint_card_effects?(effects)
  end

  defp valid_option?(_option, _valid_ids), do: false

  defp valid_effect?(%{"type" => "disable_actor"} = effect, _valid_ids),
    do: Map.keys(effect) == ["type"]

  defp valid_effect?(%{"type" => "move_actor", "location_id" => location_id} = effect, valid_ids) do
    Enum.sort(Map.keys(effect)) == ["location_id", "type"] and
      MapSet.member?(valid_ids.locations, location_id)
  end

  defp valid_effect?(
         %{"type" => "private_case_cards", "case_card_ids" => ids} = effect,
         valid_ids
       ) do
    Enum.sort(Map.keys(effect)) == ["case_card_ids", "type"] and valid_id_list?(ids) and
      MapSet.subset?(MapSet.new(ids), valid_ids.case_cards)
  end

  defp valid_effect?(
         %{"type" => "public_case_cards", "case_card_ids" => ids} = effect,
         valid_ids
       ) do
    Enum.sort(Map.keys(effect)) == ["case_card_ids", "type"] and valid_id_list?(ids) and
      MapSet.subset?(MapSet.new(ids), valid_ids.case_cards)
  end

  defp valid_effect?(%{"type" => "reveal_suspects", "suspect_ids" => ids} = effect, valid_ids) do
    Enum.sort(Map.keys(effect)) == ["suspect_ids", "type"] and valid_id_list?(ids) and
      MapSet.subset?(MapSet.new(ids), valid_ids.suspects)
  end

  defp valid_effect?(_effect, _valid_ids), do: false

  defp normalize_option(option) do
    %{
      id: option["id"],
      label: option["label"],
      action_cost: option["action_cost"],
      scratch_cost: option["scratch_cost"],
      once: option["once"],
      choice_group: option["choice_group"],
      effects: option["effects"]
    }
  end

  defp public_option(option) do
    public = Map.take(option, [:id, :label, :action_cost, :scratch_cost])

    case Map.get(option, :choice_group) do
      nil -> public
      choice_group -> Map.put(public, :choice_group, choice_group)
    end
  end

  defp effect_ids(option, effect_type, id_key) do
    option.effects
    |> Enum.filter(&(&1["type"] == effect_type))
    |> Enum.flat_map(& &1[id_key])
    |> Enum.uniq()
  end

  defp valid_choice_groups?(options) do
    group_counts =
      options
      |> Enum.map(& &1["choice_group"])
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    Enum.all?(group_counts, fn {_group, count} -> count >= 2 end)
  end

  defp disjoint_card_effects?(effects) do
    private_ids = effect_ids(%{effects: effects}, "private_case_cards", "case_card_ids")
    public_ids = effect_ids(%{effects: effects}, "public_case_cards", "case_card_ids")

    MapSet.disjoint?(MapSet.new(private_ids), MapSet.new(public_ids))
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
