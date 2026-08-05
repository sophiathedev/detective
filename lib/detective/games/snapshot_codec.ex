defmodule Detective.Games.SnapshotCodec do
  @moduledoc false

  alias Detective.Games.State

  @schema_version State.schema_version()

  def dump(%State{} = state) do
    state
    |> Map.from_struct()
    |> json_value()
  end

  def load(%{"schema_version" => schema_version} = data)
      when schema_version in [1, 2, 3, 4, 5, 6, @schema_version] do
    with {:ok, status} <- status(data["status"]),
         {:ok, phase} <- phase(data["phase"]),
         {:ok, paused_from_phase} <- optional_phase(data["paused_from_phase"]),
         {:ok, pause_reason} <- optional_reason(data["pause_reason"]),
         {:ok, players} <- load_players(data["players"]),
         {:ok, locations} <- load_locations(data["locations"]),
         {:ok, suspects} <- load_suspects(data["suspects"]),
         {:ok, special_actors} <- load_special_actors(data["special_actors"] || %{}) do
      {:ok,
       %State{
         schema_version: @schema_version,
         game_id: data["game_id"],
         case_version_id: data["case_version_id"],
         status: status,
         phase: phase,
         paused_from_phase: paused_from_phase,
         pause_reason: pause_reason,
         paused_player_ids: data["paused_player_ids"] || [],
         version: data["version"],
         day: data["day"],
         days_remaining: data["days_remaining"],
         chisel_player_id: data["chisel_player_id"],
         current_detective_id: data["current_detective_id"],
         detective_order: data["detective_order"],
         players: players,
         locations: locations,
         suspects: suspects,
         special_actors: special_actors,
         case_definition: data["case_definition"],
         public_case_card_ids: data["public_case_card_ids"] || [],
         archived_searches: data["archived_searches"] || [],
         taken_evidence: data["taken_evidence"] || %{},
         triggered_special_rule_ids: data["triggered_special_rule_ids"] || [],
         pending_action: data["pending_action"],
         winner: data["winner"],
         public_history: data["public_history"] || []
       }}
    end
  end

  def load(_data), do: {:error, :unsupported_snapshot}

  def json_value(nil), do: nil
  def json_value(value) when is_boolean(value), do: value
  def json_value(value) when is_binary(value) or is_number(value), do: value
  def json_value(value) when is_atom(value), do: Atom.to_string(value)
  def json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  def json_value(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {json_key(key), json_value(nested_value)}
    end)
  end

  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: to_string(key)

  defp load_players(players) when is_map(players) do
    Enum.reduce_while(players, {:ok, %{}}, fn {player_id, player}, {:ok, acc} ->
      case load_player(player) do
        {:ok, loaded_player} ->
          {:cont, {:ok, Map.put(acc, player_id, loaded_player)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp load_players(_players), do: {:error, :invalid_snapshot_players}

  defp load_player(%{"role" => "detective"} = player) do
    {:ok,
     %{
       id: player["id"],
       user_id: player["user_id"],
       display_name: player["display_name"],
       role: "detective",
       seat: player["seat"],
       location_id: player["location_id"],
       actions_remaining: player["actions_remaining"],
       scratch: player["scratch"],
       leverage_supply: player["leverage_supply"],
       leverage_on_suspects: player["leverage_on_suspects"] || %{},
       knowledge: player["knowledge"] || [],
       statements: player["statements"] || [],
       search_notes: player["search_notes"] || [],
       evidence: player["evidence"] || [],
       free_question_suspect_id: player["free_question_suspect_id"],
       solve_token_available: Map.get(player, "solve_token_available", true),
       solve_attempt: player["solve_attempt"],
       final_guess: player["final_guess"],
       kickback_day: player["kickback_day"]
     }}
  end

  defp load_player(%{"role" => "chisel"} = player) do
    {:ok,
     %{
       id: player["id"],
       user_id: player["user_id"],
       display_name: player["display_name"],
       role: "chisel",
       leverage_by_detective: player["leverage_by_detective"] || %{}
     }}
  end

  defp load_player(_player), do: {:error, :invalid_snapshot_player}

  defp load_locations(locations) when is_map(locations) do
    {:ok,
     Map.new(locations, fn {location_id, location} ->
       {location_id,
        %{
          id: location["id"],
          name: location["name"],
          type: location["type"],
          district_ids: location["district_ids"],
          x: location["x"],
          y: location["y"]
        }}
     end)}
  end

  defp load_locations(_locations), do: {:error, :invalid_snapshot_locations}

  defp load_suspects(suspects) when is_map(suspects) do
    {:ok,
     Map.new(suspects, fn {suspect_id, suspect} ->
       {suspect_id,
        %{
          id: suspect["id"],
          name: suspect["name"],
          occupation: suspect["occupation"],
          location_id: suspect["location_id"],
          revealed: Map.get(suspect, "revealed", true)
        }}
     end)}
  end

  defp load_suspects(_suspects), do: {:error, :invalid_snapshot_suspects}

  defp load_special_actors(actors) when is_map(actors) do
    Enum.reduce_while(actors, {:ok, %{}}, fn {actor_id, actor}, {:ok, acc} ->
      case load_special_actor(actor) do
        {:ok, loaded_actor} -> {:cont, {:ok, Map.put(acc, actor_id, loaded_actor)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp load_special_actors(_actors), do: {:error, :invalid_snapshot_special_actors}

  defp load_special_actor(actor) when is_map(actor) do
    with id when is_binary(id) <- actor["id"],
         name when is_binary(name) <- actor["name"],
         role when is_binary(role) <- actor["role"],
         kind when is_binary(kind) <- actor["kind"],
         location_id when is_binary(location_id) <- actor["location_id"],
         visible when is_boolean(visible) <- Map.get(actor, "visible", true),
         active when is_boolean(active) <- actor["active"],
         interaction_disabled when is_boolean(interaction_disabled) <-
           Map.get(actor, "interaction_disabled", false),
         blocks when is_list(blocks) <- actor["blocks"],
         options when is_list(options) <- actor["options"],
         used_option_ids when is_list(used_option_ids) <- actor["used_option_ids"],
         resolved_choice_groups when is_list(resolved_choice_groups) <-
           Map.get(actor, "resolved_choice_groups", []) do
      {:ok,
       %{
         id: id,
         name: name,
         role: role,
         kind: kind,
         location_id: location_id,
         visible: visible,
         active: active,
         interaction_disabled: interaction_disabled,
         blocks: blocks,
         options: Enum.map(options, &load_special_option/1),
         used_option_ids: used_option_ids,
         resolved_choice_groups: resolved_choice_groups
       }}
    else
      _invalid -> {:error, :invalid_snapshot_special_actors}
    end
  end

  defp load_special_actor(_actor), do: {:error, :invalid_snapshot_special_actors}

  defp load_special_option(option) do
    %{
      id: option["id"],
      label: option["label"],
      action_cost: option["action_cost"],
      scratch_cost: option["scratch_cost"],
      once: option["once"],
      choice_group: option["choice_group"],
      effects: option["effects"] || []
    }
  end

  defp status("active"), do: {:ok, :active}
  defp status("finished"), do: {:ok, :finished}
  defp status("paused"), do: {:ok, :paused}
  defp status(_status), do: {:error, :invalid_snapshot_status}

  defp phase("detective_turn"), do: {:ok, :detective_turn}
  defp phase("waiting_for_chisel"), do: {:ok, :waiting_for_chisel}
  defp phase("waiting_for_snitches"), do: {:ok, :waiting_for_snitches}
  defp phase("waiting_for_detective_decision"), do: {:ok, :waiting_for_detective_decision}
  defp phase("resolving_challenge"), do: {:ok, :resolving_challenge}
  defp phase("accusation"), do: {:ok, :accusation}
  defp phase("paused"), do: {:ok, :paused}
  defp phase("finished"), do: {:ok, :finished}
  defp phase(_phase), do: {:error, :invalid_snapshot_phase}

  defp optional_phase(nil), do: {:ok, nil}
  defp optional_phase(value), do: phase(value)

  defp optional_reason(nil), do: {:ok, nil}
  defp optional_reason("player_disconnected"), do: {:ok, :player_disconnected}
  defp optional_reason(_value), do: {:error, :invalid_snapshot_pause_reason}
end
