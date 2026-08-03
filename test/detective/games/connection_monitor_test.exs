defmodule Detective.Games.ConnectionMonitorTest do
  use Detective.DataCase, async: false

  import Detective.AccountsFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope

  alias Detective.Games.{
    Command,
    ConnectionMonitor,
    ConnectionMonitorSupervisor,
    Session,
    SessionSupervisor
  }

  alias Detective.{Games, Invitations}
  alias DetectiveWeb.{Endpoint, Presence}

  test "keeps a player online until their final Presence meta leaves" do
    game_id = Ecto.UUID.generate()
    [player_id, other_player_id] = player_ids()
    first_tab = start_presence_holder(game_id, player_id)
    second_tab = start_presence_holder(game_id, player_id)

    {:ok, _pid} = start_monitor(game_id, [player_id, other_player_id], :active)

    stop_presence_holder(game_id, player_id, first_tab)

    assert %{
             online_player_ids: [^player_id],
             offline_deadlines: %{^other_player_id => other_deadline},
             all_players_online: false
           } = ConnectionMonitor.sync(game_id)

    assert is_integer(other_deadline)

    stop_presence_holder(game_id, player_id, second_tab)

    assert %{online_player_ids: [], offline_deadlines: deadlines} =
             ConnectionMonitor.sync(game_id)

    assert is_integer(deadlines[player_id])
    assert is_integer(deadlines[other_player_id])
  end

  test "reconnect cancellation and unrelated tokens cannot pause the game" do
    %{game: game, player_ids: player_ids} = active_game()
    [player_id | other_player_ids] = player_ids

    Enum.each(other_player_ids, &start_presence_holder(game.id, &1))

    first_tab = start_presence_holder(game.id, player_id)
    {:ok, monitor_pid} = start_monitor(game.id, player_ids, :active)

    stop_presence_holder(game.id, player_id, first_tab)
    _ = ConnectionMonitor.sync(game.id)
    monitor_state = :sys.get_state(monitor_pid)
    timer = monitor_state.timers[player_id]

    Endpoint.subscribe("game:#{game.id}")
    returned_tab = start_presence_holder(game.id, player_id)
    _ = ConnectionMonitor.sync(game.id)
    send(monitor_pid, {:disconnect_timeout, player_id, timer.token})
    refute_receive %Phoenix.Socket.Broadcast{event: "game_paused"}

    stop_presence_holder(game.id, player_id, returned_tab)
    _ = ConnectionMonitor.sync(game.id)
    send(monitor_pid, {:disconnect_timeout, player_id, make_ref()})
    _ = :sys.get_state(monitor_pid)
    refute_receive %Phoenix.Socket.Broadcast{event: "game_paused"}, 0

    assert {:ok, state} = Session.get_state(game.id)
    assert state.status == :active
  end

  test "two simultaneous offline players yield one authoritative pause" do
    %{game: game, player_ids: player_ids} = active_game()
    [first_player_id, second_player_id] = player_ids

    Endpoint.subscribe("game:#{game.id}")
    {:ok, monitor_pid} = start_monitor(game.id, player_ids, :active)
    _ = ConnectionMonitor.sync(game.id)
    state = :sys.get_state(monitor_pid)

    Enum.each([first_player_id, second_player_id], fn id ->
      send(monitor_pid, {:disconnect_timeout, id, state.timers[id].token})
    end)

    assert_receive %Phoenix.Socket.Broadcast{event: "game_paused"}
    refute_receive %Phoenix.Socket.Broadcast{event: "game_paused"}
    assert {:ok, paused} = Session.get_state(game.id)
    assert paused.status == :paused
    assert Enum.sort(paused.paused_player_ids) == Enum.sort(player_ids)

    _ = :sys.get_state(monitor_pid)
    assert :sys.get_state(monitor_pid).game_status == :paused
    assert :sys.get_state(monitor_pid).timers == %{}
  end

  test "paused monitors track Presence without timers and finished monitors stop normally" do
    game_id = Ecto.UUID.generate()
    [online_player_id, offline_player_id] = player_ids()
    online_tab = start_presence_holder(game_id, online_player_id)
    {:ok, monitor_pid} = start_monitor(game_id, [online_player_id, offline_player_id], :paused)

    assert %{
             online_player_ids: [^online_player_id],
             offline_deadlines: %{},
             all_players_online: false
           } = ConnectionMonitor.sync(game_id)

    assert :sys.get_state(monitor_pid).timers == %{}

    :ok = ConnectionMonitor.game_status_changed(game_id, :active)
    _ = :sys.get_state(monitor_pid)

    assert is_integer(
             ConnectionMonitor.connection_state(game_id).offline_deadlines[offline_player_id]
           )

    :ok = ConnectionMonitor.game_status_changed(game_id, :paused)
    _ = :sys.get_state(monitor_pid)
    assert ConnectionMonitor.connection_state(game_id).offline_deadlines == %{}

    monitor = Process.monitor(monitor_pid)
    :ok = ConnectionMonitor.game_status_changed(game_id, :finished)
    assert_receive {:DOWN, ^monitor, :process, ^monitor_pid, :normal}

    stop_presence_holder(game_id, online_player_id, online_tab)
  end

  test "monitor restart rebuilds online players and fresh offline deadlines from Presence" do
    game_id = Ecto.UUID.generate()
    [online_player_id, offline_player_id] = player_ids()
    online_tab = start_presence_holder(game_id, online_player_id)
    {:ok, first_pid} = start_monitor(game_id, [online_player_id, offline_player_id], :active)
    first_deadline = ConnectionMonitor.sync(game_id).offline_deadlines[offline_player_id]

    monitor = Process.monitor(first_pid)
    assert :ok = DynamicSupervisor.terminate_child(ConnectionMonitorSupervisor, first_pid)
    assert_receive {:DOWN, ^monitor, :process, ^first_pid, :shutdown}

    {:ok, second_pid} =
      ConnectionMonitor.ensure_monitor(game_id, [online_player_id, offline_player_id], :active)

    assert second_pid != first_pid

    assert %{
             online_player_ids: [^online_player_id],
             offline_deadlines: %{^offline_player_id => second_deadline}
           } = ConnectionMonitor.sync(game_id)

    assert second_deadline >= first_deadline
    stop_presence_holder(game_id, online_player_id, online_tab)
  end

  test "abnormal exits are recreated through ensure_monitor with the authoritative status" do
    game_id = Ecto.UUID.generate()
    player_ids = player_ids()
    {:ok, first_pid} = start_monitor(game_id, player_ids, :active)

    :ok = ConnectionMonitor.game_status_changed(game_id, :paused)
    _ = :sys.get_state(first_pid)

    monitor = Process.monitor(first_pid)
    Process.exit(first_pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first_pid, :killed}

    {:ok, second_pid} = ConnectionMonitor.ensure_monitor(game_id, player_ids, :paused)
    second_state = :sys.get_state(second_pid)

    assert second_pid != first_pid
    assert second_state.game_status == :paused
    assert second_state.timers == %{}
  end

  test "finished games do not start connection monitors" do
    game_id = Ecto.UUID.generate()

    assert {:error, :game_finished} = start_monitor(game_id, player_ids(), :finished)
  end

  test "resume requires fresh Presence but duplicate replay bypasses the online gate" do
    %{game: game, host: host, player_ids: player_ids} = active_game()

    assert {:ok, %{state: paused}} = Session.pause_for_disconnect(game.id, player_ids)

    tabs = Enum.map(player_ids, &{&1, start_presence_holder(game.id, &1)})
    command_id = Ecto.UUID.generate()

    resume = %Command{
      command_id: command_id,
      type: :resume_game,
      expected_version: paused.version,
      payload: %{}
    }

    assert {:ok, %{duplicate: false, state: resumed}} =
             Session.execute(game.id, host.id, resume)

    assert resumed.status == :active

    Enum.each(tabs, fn {player_id, pid} -> stop_presence_holder(game.id, player_id, pid) end)

    assert {:ok, %{duplicate: true, version: version}} =
             Session.execute(game.id, host.id, resume)

    assert version == resumed.version

    assert {:ok, %{state: paused_again}} = Session.pause_for_disconnect(game.id, player_ids)

    offline_resume = %Command{
      command_id: Ecto.UUID.generate(),
      type: :resume_game,
      expected_version: paused_again.version,
      payload: %{}
    }

    assert {:error, :players_offline} = Session.execute(game.id, host.id, offline_resume)
  end

  defp active_game do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: lobby}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    assert {:ok, _result} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               lobby.current_version
             )

    assert {:ok, state} = Session.get_state(game.id)
    cleanup_game_processes(game.id)

    %{game: game, host: host, detective: detective, player_ids: Map.keys(state.players)}
  end

  defp player_ids, do: [Ecto.UUID.generate(), Ecto.UUID.generate()]

  defp start_monitor(game_id, player_ids, status) do
    cleanup_monitor_on_exit(game_id)
    ConnectionMonitor.ensure_monitor(game_id, player_ids, status)
  end

  defp cleanup_game_processes(game_id) do
    cleanup_monitor_on_exit(game_id)

    on_exit(fn ->
      case Registry.lookup(Detective.GameRegistry, game_id) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(SessionSupervisor, pid)
        [] -> :ok
      end
    end)
  end

  defp cleanup_monitor_on_exit(game_id) do
    on_exit(fn ->
      case Registry.lookup(Detective.GameRegistry, {:connection_monitor, game_id}) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(ConnectionMonitorSupervisor, pid)
        [] -> :ok
      end
    end)
  end

  defp start_presence_holder(game_id, player_id) do
    parent = self()

    child_spec =
      Supervisor.child_spec(
        {Task,
         fn ->
           {:ok, _ref} =
             Presence.track(
               self(),
               ConnectionMonitor.presence_topic(game_id),
               player_id,
               %{online_at: System.system_time(:second)}
             )

           send(parent, {:presence_tracked, self()})

           receive do
             :stop -> :ok
           end
         end},
        id: {:presence_holder, make_ref()}
      )

    pid = start_supervised!(child_spec)
    assert_receive {:presence_tracked, ^pid}
    await_presence_count(game_id, player_id, fn count -> count > 0 end)
    pid
  end

  defp stop_presence_holder(game_id, player_id, pid) do
    previous_count = presence_count(game_id, player_id)
    monitor = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
    await_presence_count(game_id, player_id, &(&1 < previous_count))
  end

  defp await_presence_count(game_id, player_id, predicate) do
    topic = ConnectionMonitor.presence_topic(game_id)
    :ok = Endpoint.subscribe(topic)

    if predicate.(presence_count(game_id, player_id)) do
      :ok
    else
      assert_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "presence_diff"}
      await_presence_count(game_id, player_id, predicate)
    end
  end

  defp presence_count(game_id, player_id) do
    game_id
    |> ConnectionMonitor.presence_topic()
    |> Presence.list()
    |> get_in([player_id, :metas])
    |> List.wrap()
    |> length()
  end
end
