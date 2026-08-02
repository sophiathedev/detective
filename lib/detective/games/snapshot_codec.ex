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
      when schema_version == @schema_version do
    with {:ok, status} <- status(data["status"]),
         {:ok, phase} <- phase(data["phase"]),
         {:ok, players} <- load_players(data["players"]),
         {:ok, locations} <- load_locations(data["locations"]),
         {:ok, suspects} <- load_suspects(data["suspects"]) do
      {:ok,
       %State{
         schema_version: schema_version,
         game_id: data["game_id"],
         case_version_id: data["case_version_id"],
         status: status,
         phase: phase,
         version: data["version"],
         day: data["day"],
         days_remaining: data["days_remaining"],
         chisel_player_id: data["chisel_player_id"],
         current_detective_id: data["current_detective_id"],
         detective_order: data["detective_order"],
         players: players,
         locations: locations,
         suspects: suspects,
         case_definition: data["case_definition"],
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
          location_id: suspect["location_id"]
        }}
     end)}
  end

  defp load_suspects(_suspects), do: {:error, :invalid_snapshot_suspects}

  defp status("active"), do: {:ok, :active}
  defp status("finished"), do: {:ok, :finished}
  defp status("paused"), do: {:ok, :paused}
  defp status(_status), do: {:error, :invalid_snapshot_status}

  defp phase("detective_turn"), do: {:ok, :detective_turn}
  defp phase("waiting_for_chisel"), do: {:ok, :waiting_for_chisel}
  defp phase("waiting_for_detective_decision"), do: {:ok, :waiting_for_detective_decision}
  defp phase("resolving_challenge"), do: {:ok, :resolving_challenge}
  defp phase("accusation"), do: {:ok, :accusation}
  defp phase("paused"), do: {:ok, :paused}
  defp phase("finished"), do: {:ok, :finished}
  defp phase(_phase), do: {:error, :invalid_snapshot_phase}
end
