defmodule Detective.Games.InvestigationStats do
  @moduledoc false

  @counter_by_event %{
    "player_moved" => "moves",
    "location_searched" => "searches",
    "suspect_searched" => "searches",
    "interrogation_started" => "interrogations",
    "challenge_succeeded" => "challenges",
    "challenge_failed" => "challenges"
  }

  @counters ~w(moves searches interrogations challenges successful_challenges)

  def empty do
    Map.new(@counters, &{&1, 0})
    |> Map.put("by_player", %{})
  end

  def record(stats, entry) when is_map(entry) do
    stats = normalize(stats)
    type = value(entry, :type)

    case Map.fetch(@counter_by_event, type) do
      {:ok, counter} ->
        stats
        |> increment(counter)
        |> increment_player(value(entry, :player_id), counter)
        |> maybe_record_successful_challenge(type, value(entry, :player_id))

      :error ->
        stats
    end
  end

  def from_history(history) when is_list(history) do
    Enum.reduce(Enum.reverse(history), empty(), &record(&2, &1))
  end

  def normalize(stats) when is_map(stats) do
    normalized =
      Map.new(@counters, fn counter ->
        {counter, non_negative_integer(Map.get(stats, counter))}
      end)

    Map.put(normalized, "by_player", normalize_players(Map.get(stats, "by_player")))
  end

  def normalize(_stats), do: empty()

  def investigation(stats) do
    stats = normalize(stats)

    %{
      moves: stats["moves"],
      searches: stats["searches"],
      interrogations: stats["interrogations"],
      challenges: stats["challenges"],
      successful_challenges: stats["successful_challenges"]
    }
  end

  def player_activity(stats, player_id) do
    stats
    |> normalize()
    |> get_in(["by_player", player_id])
    |> normalize_player()
    |> Map.take(~w(moves searches interrogations challenges))
    |> Map.new(fn {key, count} -> {String.to_existing_atom(key), count} end)
  end

  defp maybe_record_successful_challenge(stats, "challenge_succeeded", player_id) do
    stats
    |> increment("successful_challenges")
    |> increment_player(player_id, "successful_challenges")
  end

  defp maybe_record_successful_challenge(stats, _type, _player_id), do: stats

  defp increment(stats, counter), do: Map.update!(stats, counter, &(&1 + 1))

  defp increment_player(stats, player_id, counter) when is_binary(player_id) do
    update_in(stats, ["by_player"], fn players ->
      Map.update(players, player_id, increment(empty_player(), counter), fn player ->
        player
        |> normalize_player()
        |> increment(counter)
      end)
    end)
  end

  defp increment_player(stats, _player_id, _counter), do: stats

  defp normalize_players(players) when is_map(players) do
    Map.new(players, fn {player_id, stats} -> {player_id, normalize_player(stats)} end)
  end

  defp normalize_players(_players), do: %{}

  defp normalize_player(stats) when is_map(stats) do
    Map.new(@counters, fn counter ->
      {counter, non_negative_integer(Map.get(stats, counter))}
    end)
  end

  defp normalize_player(_stats), do: empty_player()

  defp empty_player, do: Map.new(@counters, &{&1, 0})

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value), do: 0

  defp value(entry, key), do: Map.get(entry, key) || Map.get(entry, Atom.to_string(key))
end
