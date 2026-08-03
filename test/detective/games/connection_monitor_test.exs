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

  setup do
    previous_grace_ms = Application.fetch_env!(:detective, :disconnect_grace_ms)
    Application.put_env(:detective, :disconnect_grace_ms, 60_000)

    on_exit(fn ->
      Application.put_env(:detective, :disconnect_grace_ms, previous_grace_ms)
    end)

    :ok
  end

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

  test "a reconnect-at-expiry preserves every other player's timer" do
    game_id = Ecto.UUID.generate()
    [first_player_id, second_player_id] = player_ids()
    first_tab = start_presence_holder(game_id, first_player_id)
    second_tab = start_presence_holder(game_id, second_player_id)
    {:ok, monitor_pid} = start_monitor(game_id, [first_player_id, second_player_id], :active)

    stop_presence_holder(game_id, first_player_id, first_tab)
    _ = ConnectionMonitor.sync(game_id)
    first_timer = :sys.get_state(monitor_pid).timers[first_player_id]

    stop_presence_holder(game_id, second_player_id, second_tab)
    _ = ConnectionMonitor.sync(game_id)
    staggered_state = :sys.get_state(monitor_pid)
    second_timer = staggered_state.timers[second_player_id]
    assert staggered_state.timers[first_player_id].token == first_timer.token

    :ok = :sys.suspend(monitor_pid)
    send(monitor_pid, {:disconnect_timeout, first_player_id, first_timer.token})
    returned_first_tab = start_presence_holder(game_id, first_player_id)
    :ok = :sys.resume(monitor_pid)
    final_state = :sys.get_state(monitor_pid)

    assert final_state.online_player_ids == MapSet.new([first_player_id])
    refute Map.has_key?(final_state.timers, first_player_id)
    assert final_state.timers[second_player_id].token == second_timer.token

    assert final_state.timers[second_player_id].deadline_unix_ms ==
             second_timer.deadline_unix_ms

    stop_presence_holder(game_id, first_player_id, returned_first_tab)
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

    :ok = ConnectionMonitor.game_status_changed(game_id, :active, 2)
    _ = :sys.get_state(monitor_pid)

    assert is_integer(
             ConnectionMonitor.connection_state(game_id).offline_deadlines[offline_player_id]
           )

    :ok = ConnectionMonitor.game_status_changed(game_id, :paused, 3)
    _ = :sys.get_state(monitor_pid)
    assert ConnectionMonitor.connection_state(game_id).offline_deadlines == %{}

    monitor = Process.monitor(monitor_pid)
    :ok = ConnectionMonitor.game_status_changed(game_id, :finished, 4)
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
      ConnectionMonitor.ensure_monitor(
        game_id,
        [online_player_id, offline_player_id],
        :active,
        1
      )

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

    :ok = ConnectionMonitor.game_status_changed(game_id, :paused, 2)
    _ = :sys.get_state(first_pid)

    monitor = Process.monitor(first_pid)
    Process.exit(first_pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first_pid, :killed}

    {:ok, second_pid} = ConnectionMonitor.ensure_monitor(game_id, player_ids, :paused, 2)
    second_state = :sys.get_state(second_pid)

    assert second_pid != first_pid
    assert second_state.game_status == :paused
    assert second_state.timers == %{}
  end

  test "finished games do not start connection monitors" do
    game_id = Ecto.UUID.generate()

    assert {:error, :game_finished} = start_monitor(game_id, player_ids(), :finished)
  end

  test "ensure_monitor applies paused status to an existing active monitor" do
    game_id = Ecto.UUID.generate()
    player_ids = player_ids()
    {:ok, monitor_pid} = start_monitor(game_id, player_ids, :active)

    assert map_size(:sys.get_state(monitor_pid).timers) == length(player_ids)

    assert {:ok, ^monitor_pid} =
             ConnectionMonitor.ensure_monitor(game_id, player_ids, :paused, 2)

    state = :sys.get_state(monitor_pid)
    assert state.game_status == :paused
    assert state.timers == %{}
  end

  test "ensure_monitor stops an existing monitor for a finished game" do
    game_id = Ecto.UUID.generate()
    player_ids = player_ids()
    {:ok, monitor_pid} = start_monitor(game_id, player_ids, :active)
    monitor = Process.monitor(monitor_pid)

    assert {:error, :game_finished} =
             ConnectionMonitor.ensure_monitor(game_id, player_ids, :finished, 2)

    assert_receive {:DOWN, ^monitor, :process, ^monitor_pid, :normal}
  end

  test "a delayed paused after_join seed cannot overwrite a resumed monitor" do
    %{game: game, host: host, player_ids: player_ids} = active_game()

    assert {:ok, %{state: paused}} = Session.pause_for_disconnect(game.id, player_ids)

    tabs = Enum.map(player_ids, &{&1, start_presence_holder(game.id, &1)})
    {:ok, monitor_pid} = start_monitor(game.id, player_ids, :paused)

    resume = %Command{
      command_id: Ecto.UUID.generate(),
      type: :resume_game,
      expected_version: paused.version,
      payload: %{}
    }

    assert {:ok, %{state: resumed}} = Session.execute(game.id, host.id, resume)
    _ = :sys.get_state(monitor_pid)

    assert {:ok, ^monitor_pid} =
             ensure_monitor_versioned(game.id, player_ids, :paused, paused.version)

    monitor_state = :sys.get_state(monitor_pid)
    assert monitor_state.game_status == :active
    assert Map.get(monitor_state, :game_version) == resumed.version

    Enum.each(tabs, fn {player_id, pid} -> stop_presence_holder(game.id, player_id, pid) end)
  end

  test "a delayed active after_join seed cannot revive a finished monitor" do
    %{game: game, detective: detective, player_ids: player_ids} = active_game()
    assert {:ok, active} = Session.get_state(game.id)
    {:ok, monitor_pid} = start_monitor(game.id, player_ids, :active)
    monitor = Process.monitor(monitor_pid)

    assert {:ok, %{state: finished}} = finish_game(game.id, detective.id, active.version)
    assert finished.status == :finished
    assert_receive {:DOWN, ^monitor, :process, ^monitor_pid, :normal}

    assert {:error, :game_finished} =
             ensure_monitor_versioned(game.id, player_ids, :active, active.version)

    _ = :sys.get_state(ConnectionMonitorSupervisor)

    assert [] ==
             Registry.lookup(Detective.GameRegistry, {:connection_monitor, game.id})
  end

  test "Session startup errors keep the monitor alive with a fresh retry timer" do
    host = user_fixture()
    %{game: game} = game_fixture(host)
    [player_id | _rest] = player_ids()
    {:ok, monitor_pid} = start_monitor(game.id, [player_id], :active)
    first_timer = :sys.get_state(monitor_pid).timers[player_id]
    monitor = Process.monitor(monitor_pid)

    send(monitor_pid, {:disconnect_timeout, player_id, first_timer.token})
    second_timer = :sys.get_state(monitor_pid).timers[player_id]

    refute_receive {:DOWN, ^monitor, :process, ^monitor_pid, _reason}, 0
    assert second_timer.token != first_timer.token

    send(monitor_pid, {:disconnect_timeout, player_id, second_timer.token})
    third_timer = :sys.get_state(monitor_pid).timers[player_id]

    refute_receive {:DOWN, ^monitor, :process, ^monitor_pid, _reason}, 0
    assert third_timer.token != second_timer.token
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

  test "Resume validates status and role before the Presence gate" do
    %{game: game, host: host, detective: detective, player_ids: player_ids} = active_game()
    assert {:ok, active} = Session.get_state(game.id)

    active_resume = %Command{
      command_id: Ecto.UUID.generate(),
      type: :resume_game,
      expected_version: active.version,
      payload: %{}
    }

    assert {:error, :game_not_paused} = Session.execute(game.id, host.id, active_resume)

    assert {:ok, %{state: paused}} = Session.pause_for_disconnect(game.id, player_ids)

    detective_resume = %Command{
      command_id: Ecto.UUID.generate(),
      type: :resume_game,
      expected_version: paused.version,
      payload: %{}
    }

    assert {:error, :wrong_role} =
             Session.execute(game.id, detective.id, detective_resume)

    host_resume = %{detective_resume | command_id: Ecto.UUID.generate()}
    assert {:error, :players_offline} = Session.execute(game.id, host.id, host_resume)
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

  defp finish_game(game_id, detective_id, version) do
    assert {:ok, %{version: placed_version}} =
             Session.execute(game_id, detective_id, %Command{
               command_id: Ecto.UUID.generate(),
               type: :place,
               expected_version: version,
               payload: %{"location_id" => "central-precinct"}
             })

    assert {:ok, %{version: searched_version}} =
             Session.execute(game_id, detective_id, %Command{
               command_id: Ecto.UUID.generate(),
               type: :search_location,
               expected_version: placed_version,
               payload: %{}
             })

    assert {:ok, %{version: next_day_version}} =
             Session.execute(game_id, detective_id, %Command{
               command_id: Ecto.UUID.generate(),
               type: :end_turn,
               expected_version: searched_version,
               payload: %{}
             })

    Session.execute(game_id, detective_id, %Command{
      command_id: Ecto.UUID.generate(),
      type: :accuse,
      expected_version: next_day_version,
      payload: %{
        "suspect_id" => "night-clerk",
        "weapon_id" => "sealed-ledger",
        "motive_id" => "cover-up"
      }
    })
  end

  defp ensure_monitor_versioned(game_id, player_ids, status, version) do
    ConnectionMonitor.ensure_monitor(game_id, player_ids, status, version)
  end

  defp start_monitor(game_id, player_ids, status, version \\ 1) do
    cleanup_monitor_on_exit(game_id)
    ConnectionMonitor.ensure_monitor(game_id, player_ids, status, version)
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
