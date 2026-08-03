defmodule Detective.Games.ConnectionMonitorSupervisor do
  use DynamicSupervisor

  alias Detective.Games.ConnectionMonitor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

  def ensure_monitor(_game_id, _player_ids, :finished), do: {:error, :game_finished}

  def ensure_monitor(game_id, player_ids, game_status) do
    case Registry.lookup(Detective.GameRegistry, {:connection_monitor, game_id}) do
      [{pid, _value}] ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          start_monitor(game_id, player_ids, game_status, 2)
        end

      [] ->
        start_monitor(game_id, player_ids, game_status, 2)
    end
  end

  defp start_monitor(game_id, player_ids, game_status, attempts_left) do
    case DynamicSupervisor.start_child(
           __MODULE__,
           {ConnectionMonitor, {game_id, player_ids, game_status}}
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        cond do
          Process.alive?(pid) ->
            {:ok, pid}

          attempts_left > 0 ->
            _ = :sys.get_state(__MODULE__)
            start_monitor(game_id, player_ids, game_status, attempts_left - 1)

          true ->
            {:error, :connection_monitor_unavailable}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
