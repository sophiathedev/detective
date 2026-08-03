defmodule Detective.Games.ConnectionMonitor do
  use GenServer

  alias Detective.Games.{ConnectionMonitorSupervisor, Session}
  alias DetectiveWeb.{Endpoint, Presence}

  def start_link({game_id, player_ids, game_status}) do
    GenServer.start_link(
      __MODULE__,
      {game_id, player_ids, game_status},
      name: via(game_id)
    )
  end

  def child_spec({game_id, _player_ids, _game_status} = init_arg) do
    %{
      id: {__MODULE__, game_id},
      start: {__MODULE__, :start_link, [init_arg]},
      restart: :temporary,
      type: :worker
    }
  end

  def ensure_monitor(game_id, player_ids, game_status) do
    ConnectionMonitorSupervisor.ensure_monitor(game_id, player_ids, game_status)
  end

  def presence_topic(game_id), do: "game_presence:#{game_id}"

  def sync(game_id), do: call_monitor(game_id, :sync)

  def connection_state(game_id), do: call_monitor(game_id, :connection_state)

  def all_players_online?(game_id), do: call_monitor(game_id, :all_players_online)

  def game_status_changed(game_id, status) when status in [:active, :paused, :finished] do
    case monitor_pid(game_id) do
      {:ok, pid} -> GenServer.cast(pid, {:game_status_changed, status})
      {:error, :monitor_not_found} -> :ok
    end
  end

  @impl true
  def init({game_id, player_ids, game_status}) do
    :ok = Endpoint.subscribe(presence_topic(game_id))

    state = %{
      game_id: game_id,
      player_ids: MapSet.new(player_ids),
      game_status: game_status,
      online_player_ids: MapSet.new(),
      timers: %{}
    }

    {:ok, reconcile(state)}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    state = reconcile(state)
    {:reply, public_state(state), state}
  end

  def handle_call(:connection_state, _from, state) do
    {:reply, public_state(state), state}
  end

  def handle_call(:all_players_online, _from, state) do
    state = reconcile(state)
    {:reply, MapSet.equal?(state.online_player_ids, state.player_ids), state}
  end

  @impl true
  def handle_cast({:game_status_changed, :finished}, state) do
    {:stop, :normal, cancel_all_timers(%{state | game_status: :finished})}
  end

  def handle_cast({:game_status_changed, status}, state) when status in [:active, :paused] do
    {:noreply, reconcile(%{state | game_status: status})}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff"},
        %{game_id: game_id} = state
      ) do
    if topic == presence_topic(game_id) do
      {:noreply, reconcile(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:disconnect_timeout, player_id, token}, state) do
    case Map.get(state.timers, player_id) do
      %{token: ^token} -> handle_current_timeout(state, player_id)
      _stale_or_missing -> {:noreply, state}
    end
  end

  defp handle_current_timeout(state, player_id) do
    state = state |> cancel_all_timers() |> reconcile()

    if state.game_status == :active and not MapSet.member?(state.online_player_ids, player_id) do
      offline_player_ids =
        state.player_ids
        |> MapSet.difference(state.online_player_ids)
        |> Enum.sort()

      :ok = Session.request_pause_for_disconnect(state.game_id, offline_player_ids)
    end

    {:noreply, state}
  end

  defp reconcile(state) do
    online_player_ids = online_player_ids(state)

    state =
      state
      |> Map.put(:online_player_ids, online_player_ids)
      |> cancel_unneeded_timers()
      |> schedule_missing_timers()

    :ok = broadcast_connection_state(state)
    state
  end

  defp online_player_ids(state) do
    state.game_id
    |> presence_topic()
    |> Presence.list()
    |> Enum.reduce(MapSet.new(), fn
      {player_id, %{metas: [_meta | _rest]}}, online ->
        if MapSet.member?(state.player_ids, player_id) do
          MapSet.put(online, player_id)
        else
          online
        end

      {_player_id, _presence}, online ->
        online
    end)
  end

  defp cancel_unneeded_timers(state) do
    timers =
      Enum.reduce(state.timers, %{}, fn {player_id, timer}, kept ->
        if state.game_status == :active and
             not MapSet.member?(state.online_player_ids, player_id) do
          Map.put(kept, player_id, timer)
        else
          cancel_timer(timer)
          kept
        end
      end)

    %{state | timers: timers}
  end

  defp schedule_missing_timers(%{game_status: :active} = state) do
    absent_player_ids = MapSet.difference(state.player_ids, state.online_player_ids)

    timers =
      Enum.reduce(absent_player_ids, state.timers, fn player_id, timers ->
        Map.put_new_lazy(timers, player_id, fn -> schedule_timer(player_id) end)
      end)

    %{state | timers: timers}
  end

  defp schedule_missing_timers(state), do: state

  defp schedule_timer(player_id) do
    grace_ms = Application.fetch_env!(:detective, :disconnect_grace_ms)
    token = make_ref()

    %{
      token: token,
      timer_ref: Process.send_after(self(), {:disconnect_timeout, player_id, token}, grace_ms),
      deadline_unix_ms: System.system_time(:millisecond) + grace_ms
    }
  end

  defp cancel_all_timers(state) do
    Enum.each(state.timers, fn {_player_id, timer} -> cancel_timer(timer) end)
    %{state | timers: %{}}
  end

  defp cancel_timer(%{timer_ref: timer_ref}) do
    _ = Process.cancel_timer(timer_ref, async: true, info: false)
    :ok
  end

  defp broadcast_connection_state(state) do
    Endpoint.broadcast("game:#{state.game_id}", "connection_state", public_state(state))
  end

  defp public_state(state) do
    %{
      online_player_ids: state.online_player_ids |> Enum.sort(),
      offline_deadlines:
        Map.new(state.timers, fn {player_id, timer} ->
          {player_id, timer.deadline_unix_ms}
        end),
      all_players_online: MapSet.equal?(state.online_player_ids, state.player_ids)
    }
  end

  defp call_monitor(game_id, message) do
    with {:ok, pid} <- monitor_pid(game_id) do
      GenServer.call(pid, message)
    end
  end

  defp monitor_pid(game_id) do
    case Registry.lookup(Detective.GameRegistry, {:connection_monitor, game_id}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :monitor_not_found}
    end
  end

  defp via(game_id) do
    {:via, Registry, {Detective.GameRegistry, {:connection_monitor, game_id}}}
  end
end
