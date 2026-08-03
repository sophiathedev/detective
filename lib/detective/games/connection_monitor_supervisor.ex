defmodule Detective.Games.ConnectionMonitorSupervisor do
  use DynamicSupervisor

  alias Detective.Games.ConnectionMonitor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

  def ensure_monitor(game_id, player_ids, :finished) do
    case Registry.lookup(Detective.GameRegistry, {:connection_monitor, game_id}) do
      [{pid, _value}] -> ensure_finished(pid, player_ids)
      [] -> :ok
    end

    {:error, :game_finished}
  end

  def ensure_monitor(game_id, player_ids, game_status) do
    case Registry.lookup(Detective.GameRegistry, {:connection_monitor, game_id}) do
      [{pid, _value}] ->
        ensure_existing_or_start(pid, game_id, player_ids, game_status, 2)

      [] ->
        start_monitor(game_id, player_ids, game_status, 2)
    end
  end

  defp ensure_existing_or_start(pid, game_id, player_ids, game_status, attempts_left) do
    cond do
      Process.alive?(pid) ->
        try do
          :ok = ConnectionMonitor.ensure_state(pid, player_ids, game_status)
          {:ok, pid}
        catch
          :exit, _reason ->
            if attempts_left > 0 do
              retry_start(game_id, player_ids, game_status, attempts_left)
            else
              {:error, :connection_monitor_unavailable}
            end
        end

      attempts_left > 0 ->
        retry_start(game_id, player_ids, game_status, attempts_left)

      true ->
        {:error, :connection_monitor_unavailable}
    end
  end

  defp retry_start(game_id, player_ids, game_status, attempts_left) do
    _ = :sys.get_state(__MODULE__)
    start_monitor(game_id, player_ids, game_status, attempts_left - 1)
  end

  defp ensure_finished(pid, player_ids) do
    if Process.alive?(pid) do
      try do
        ConnectionMonitor.ensure_state(pid, player_ids, :finished)
      catch
        :exit, _reason -> :ok
      end
    else
      :ok
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
        ensure_existing_or_start(pid, game_id, player_ids, game_status, attempts_left)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
