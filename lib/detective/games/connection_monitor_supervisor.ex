defmodule Detective.Games.ConnectionMonitorSupervisor do
  use DynamicSupervisor

  alias Detective.Games.{ConnectionMonitor, Persistence}

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

  def ensure_monitor(game_id, player_ids, :finished, game_version) do
    case Registry.lookup(Detective.GameRegistry, {:connection_monitor, game_id}) do
      [{pid, _value}] -> ensure_finished(pid, player_ids, game_version)
      [] -> :ok
    end

    {:error, :game_finished}
  end

  def ensure_monitor(game_id, player_ids, game_status, game_version) do
    case Registry.lookup(Detective.GameRegistry, {:connection_monitor, game_id}) do
      [{pid, _value}] ->
        ensure_existing_or_start(pid, game_id, player_ids, game_status, game_version, 2)

      [] ->
        start_monitor(game_id, player_ids, game_status, game_version, 2)
    end
  end

  defp ensure_existing_or_start(
         pid,
         game_id,
         player_ids,
         game_status,
         game_version,
         attempts_left
       ) do
    try do
      :ok = ConnectionMonitor.ensure_state(pid, player_ids, game_status, game_version)
      {:ok, pid}
    catch
      :exit, _reason ->
        if attempts_left > 0 do
          retry_start(game_id, player_ids, game_status, game_version, attempts_left)
        else
          {:error, :connection_monitor_unavailable}
        end
    end
  end

  defp retry_start(game_id, player_ids, game_status, game_version, attempts_left) do
    _ = :sys.get_state(__MODULE__)
    start_monitor(game_id, player_ids, game_status, game_version, attempts_left - 1)
  end

  defp ensure_finished(pid, player_ids, game_version) do
    try do
      ConnectionMonitor.ensure_state(pid, player_ids, :finished, game_version)
    catch
      :exit, _reason -> :ok
    end
  end

  defp start_monitor(game_id, player_ids, game_status, game_version, attempts_left) do
    seed = authoritative_seed(game_id, player_ids, game_status, game_version)

    if seed.game_status == :finished do
      {:error, :game_finished}
    else
      do_start_monitor(game_id, seed, attempts_left)
    end
  end

  defp do_start_monitor(game_id, seed, attempts_left) do
    case DynamicSupervisor.start_child(
           __MODULE__,
           {ConnectionMonitor, {game_id, seed.player_ids, seed.game_status, seed.game_version}}
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        ensure_existing_or_start(
          pid,
          game_id,
          seed.player_ids,
          seed.game_status,
          seed.game_version,
          attempts_left
        )

      :ignore ->
        {:error, :game_finished}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authoritative_seed(game_id, player_ids, game_status, game_version) do
    requested = %{
      player_ids: player_ids,
      game_status: game_status,
      game_version: game_version
    }

    case Persistence.connection_monitor_seed(game_id) do
      {:ok, persisted} when persisted.game_version >= game_version -> persisted
      _missing_or_older -> requested
    end
  end
end
