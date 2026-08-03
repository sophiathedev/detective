# Game Reconnect and Pause Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Add multi-tab-aware Presence tracking, a 180-second disconnect grace period, persisted pause, reconnect synchronization, and Chisel-controlled resume.

**Architecture:** Each game gets a ConnectionMonitor that derives connectivity from an internal Phoenix Presence topic and owns disconnect timers. Expired timers request a pure system transition through the existing serialized GameSession; pause and resume are persisted as events and snapshots, while ephemeral connection state is broadcast separately to LiveSvelte.

**Tech Stack:** Elixir, Phoenix 1.8 Channels/PubSub/Presence, OTP Registry and DynamicSupervisor, Ecto/PostgreSQL, ExUnit, LiveSvelte/Svelte 5, Tailwind CSS v4, Playwright CLI.

## Global Constraints

- Default disconnect grace: exactly 180_000 milliseconds.
- A player stays online while at least one game-channel Presence meta remains.
- Reconnect before expiry must not change game state or version.
- Pause and resume pass through GameSession, Ecto events, snapshots, and versioning.
- Only the Chisel may resume, and every active game player must be online.
- Preserve prior phase, pending action, turn data, and secret data exactly.
- Keep raw Presence on game_presence:<game_id>; broadcast only sanitized data.
- Add no routes. The game remains in the existing authenticated live_session :require_authenticated_user because only logged-in members may play.
- Keep Tailwind v4 imports. No DaisyUI, @apply, or inline scripts.
- Prefix shell commands with rtk and use apply_patch for source edits.
- Stage only task files. Preserve .agents/, output/, and skills-lock.json.
- Finish with mix precommit, Playwright QA, and caveman-style commits.

## File Structure

- lib/detective/games/state.ex: persisted pause metadata and snapshot version.
- lib/detective/games/snapshot_codec.ex: backward-compatible pause serialization.
- lib/detective/games/engine.ex: pure pause transition and Chisel resume.
- lib/detective/games/persistence.ex: transactional system transitions.
- lib/detective/games/session.ex: serialized pause API and online resume gate.
- lib/detective/games/connection_monitor.ex: Presence reconciliation and timers.
- lib/detective/games/connection_monitor_supervisor.ex: one monitor per game.
- lib/detective_web/channels/game_channel.ex: authorized Presence registration.
- assets/svelte/GameBook.svelte: offline marks, countdown, seal, and Resume.
- assets/css/app.css: pause-seal presentation and animation.

---

### Task 1: Persist the paused state shape

**Files:**
- Modify: lib/detective/games/state.ex
- Modify: lib/detective/games/snapshot_codec.ex
- Modify: lib/detective/games/game.ex
- Create via generator: the one priv/repo/migrations/*_allow_paused_game_status.exs file printed by mix ecto.gen.migration
- Modify: test/detective/games/snapshot_codec_test.exs

**Interfaces:**
- Produces: State.paused_from_phase, State.pause_reason, State.paused_player_ids.
- Produces: snapshot schema 3 while loading schemas 1 and 2.
- Produces: database and changeset support for status "paused".

- [ ] **Step 1: Write the failing snapshot round-trip test**

~~~elixir
test "paused snapshots preserve prior phase and pending action" do
  state = %State{
    game_id: Ecto.UUID.generate(),
    case_version_id: Ecto.UUID.generate(),
    players: %{},
    locations: %{},
    suspects: %{}
  }

  paused = %{
    state
    | status: :paused,
      phase: :paused,
      paused_from_phase: :waiting_for_chisel,
      pause_reason: :player_disconnected,
      paused_player_ids: ["detective-player"],
      pending_action: %{"type" => "interrogation", "id" => "question-1"}
  }

  assert {:ok, restored} = paused |> SnapshotCodec.dump() |> SnapshotCodec.load()
  assert restored.paused_from_phase == :waiting_for_chisel
  assert restored.pause_reason == :player_disconnected
  assert restored.paused_player_ids == ["detective-player"]
  assert restored.pending_action == paused.pending_action
end
~~~

Add backward-compatibility coverage:

~~~elixir
test "schema two snapshots load with empty pause metadata" do
  legacy =
    %State{players: %{}, locations: %{}, suspects: %{}}
    |> SnapshotCodec.dump()
    |> Map.put("schema_version", 2)
    |> Map.drop(["paused_from_phase", "pause_reason", "paused_player_ids"])

  assert {:ok, restored} = SnapshotCodec.load(legacy)
  assert restored.paused_from_phase == nil
  assert restored.pause_reason == nil
  assert restored.paused_player_ids == []
end
~~~

- [ ] **Step 2: Verify the test fails**

Run: rtk mix test test/detective/games/snapshot_codec_test.exs

Expected: failure because pause fields are absent or not restored.

- [ ] **Step 3: Generate and implement the migration**

Run: rtk mix help ecto.gen.migration

Run: rtk mix ecto.gen.migration allow_paused_game_status

Edit the single generated file:

~~~elixir
def up do
  drop constraint(:games, :games_status_check)

  create constraint(:games, :games_status_check,
           check: "status IN ('waiting', 'active', 'paused', 'finished', 'cancelled')"
         )
end

def down do
  drop constraint(:games, :games_status_check)

  create constraint(:games, :games_status_check,
           check: "status IN ('waiting', 'active', 'finished', 'cancelled')"
         )
end
~~~

- [ ] **Step 4: Add state, codec, and changeset support**

Set State schema version to 3 and add:

~~~elixir
paused_from_phase: nil,
pause_reason: nil,
paused_player_ids: [],
~~~

Load schema versions 1, 2, and 3. Decode phase and reason with closed mappings;
never use String.to_atom/1:

~~~elixir
defp optional_phase(nil), do: {:ok, nil}
defp optional_phase(value), do: phase(value)
defp optional_reason(nil), do: {:ok, nil}
defp optional_reason("player_disconnected"), do: {:ok, :player_disconnected}
defp optional_reason(_value), do: {:error, :invalid_snapshot_pause_reason}
~~~

Restore all three fields inside the existing with expression. Add paused to
both Game status inclusion lists.

- [ ] **Step 5: Run migration and focused tests**

Run: rtk mix ecto.migrate

Run: rtk mix test test/detective/games/snapshot_codec_test.exs

Expected: pass.

- [ ] **Step 6: Format and commit**

Run: rtk mix format

Stage only Task 1 files. Commit:

~~~text
feat(game): persist paused state
~~~

---

### Task 2: Add pure pause and resume rules

**Files:**
- Modify: lib/detective/games/command.ex
- Modify: lib/detective/games/engine.ex
- Modify: lib/detective/games/rules.ex
- Modify: lib/detective/games/projections/public.ex
- Modify: test/detective/games/engine_test.exs
- Modify: test/detective/games/projections_test.exs

**Interfaces:**
- Produces: Engine.apply_system(state, {:pause_for_disconnect, player_ids}).
- Produces: internal Command type :resume_game; string parsing stays closed until Task 4 installs the Presence gate.
- Produces: game_paused and game_resumed events.
- Produces: public pause metadata and Chisel resume availability.

- [ ] **Step 1: Write failing engine tests**

~~~elixir
test "disconnect pause preserves and restores the exact phase" do
  state = awaiting_chisel_state()
  detective_id = player(state, "detective-1").id
  pending = state.pending_action

  assert {:error, :game_not_paused} =
           apply_command(state, "chisel", :resume_game)

  assert {:ok, paused, [pause_event]} =
           Engine.apply_system(state, {:pause_for_disconnect, [detective_id]})

  assert paused.status == :paused
  assert paused.phase == :paused
  assert paused.paused_from_phase == :waiting_for_chisel
  assert paused.pending_action == pending
  assert pause_event.type == :game_paused

  assert {:error, :game_paused} = apply_command(paused, "detective-1", :end_turn)
  assert {:error, :wrong_role} = apply_command(paused, "detective-1", :resume_game)

  assert {:ok, resumed, [resume_event]} =
           apply_command(paused, "chisel", :resume_game)

  assert resumed.status == :active
  assert resumed.phase == :waiting_for_chisel
  assert resumed.pending_action == pending
  assert resume_event.type == :game_resumed
end
~~~

Add a table-driven test covering detective_turn, waiting_for_chisel,
waiting_for_snitches, waiting_for_detective_decision, and accusation.

~~~elixir
test "resume restores every pausable gameplay phase" do
  phases = [
    :detective_turn,
    :waiting_for_chisel,
    :waiting_for_snitches,
    :waiting_for_detective_decision,
    :accusation
  ]

  Enum.each(phases, fn phase ->
    state = %{new_state() | phase: phase, pending_action: %{"saved_phase" => phase}}

    assert {:ok, paused, [_event]} =
             Engine.apply_system(
               state,
               {:pause_for_disconnect, [player(state, "detective-1").id]}
             )

    assert {:ok, resumed, [_event]} =
             apply_command(paused, "chisel", :resume_game)

    assert resumed.phase == phase
    assert resumed.pending_action == state.pending_action
  end)
end
~~~

- [ ] **Step 2: Verify red**

Run: rtk mix test test/detective/games/engine_test.exs

Expected: apply_system/2 and resume dispatch are missing.

- [ ] **Step 3: Implement pure transitions**

Add :resume_game to the Command @type command_type union, but do not yet add
the command_type("resume_game") string parser.

~~~elixir
def apply_system(%State{status: :active} = state, {:pause_for_disconnect, ids})
    when is_list(ids) and ids != [] do
  next_state =
    %{
      state
      | status: :paused,
        phase: :paused,
        paused_from_phase: state.phase,
        pause_reason: :player_disconnected,
        paused_player_ids: Enum.uniq(ids)
    }
    |> advance_version()

  event = %Event{
    type: :game_paused,
    public_payload: %{
      reason: "player_disconnected",
      disconnected_player_ids: next_state.paused_player_ids
    }
  }

  {:ok, next_state, [event]}
end

def apply_system(%State{status: status} = state, {:pause_for_disconnect, _ids})
    when status in [:paused, :finished],
    do: {:ok, state, []}
~~~

Dispatch :resume_game before phase-specific commands. Return :game_not_paused
for an active state. On a paused state, validate the Chisel role,
restore paused_from_phase, clear pause metadata, advance the version, and emit:

~~~elixir
%Event{
  type: :game_resumed,
  public_payload: %{
    chisel_player_id: actor.id,
    restored_phase: Atom.to_string(restored_phase)
  }
}
~~~

Every other command on paused state returns :game_paused.

- [ ] **Step 4: Add paused rules and safe projection**

Rules returns [] for paused Detectives and ["resume_game"] for the Chisel.
Public projection adds:

~~~elixir
pause:
  if(state.status == :paused,
    do: %{
      reason: Atom.to_string(state.pause_reason),
      player_ids: state.paused_player_ids,
      previous_phase: Atom.to_string(state.paused_from_phase)
    },
    else: nil
  )
~~~

Projection tests must refute solution, response_matrix, pending_action, response
text, and every Chisel-only field in the encoded public map.

~~~elixir
public_json = paused |> Public.render() |> Jason.encode!()
assert Public.render(paused).pause.player_ids == [detective_id]
refute public_json =~ "solution"
refute public_json =~ "response_matrix"
refute public_json =~ "pending_action"
refute public_json =~ "selected_response_text"
~~~

- [ ] **Step 5: Run tests**

Run: rtk mix test test/detective/games/engine_test.exs test/detective/games/projections_test.exs

Expected: pass.

- [ ] **Step 6: Format and commit**

Run: rtk mix format

Commit:

~~~text
feat(game): add pause resume rules
~~~

---

### Task 3: Persist system pauses through GameSession

**Files:**
- Modify: lib/detective/games/persistence.ex
- Modify: lib/detective/games/session.ex
- Modify: lib/detective/games/game_broadcaster.ex
- Modify: test/detective/games/runtime_test.exs

**Interfaces:**
- Consumes: Engine.apply_system/2.
- Produces: Persistence.persist_system_transition/6.
- Produces: Session.pause_for_disconnect(game_id, player_ids).
- Produces: Session.request_pause_for_disconnect(game_id, player_ids).
- Produces: persisted and broadcastable pause/resume events.

- [ ] **Step 1: Write the failing runtime test**

Open an interrogation, record pending_action, then:

~~~elixir
command_count = Repo.aggregate(CommandRecord, :count)

assert {:ok, %{version: paused_version, events: [event]}} =
         Session.pause_for_disconnect(game.id, [detective_player.id])

assert event.type == :game_paused
assert %Game{status: "paused", phase: "paused", current_version: ^paused_version} =
         Repo.get!(Game, game.id)

restart_session(game.id)
assert {:ok, restored} = Session.get_state(game.id)
assert restored.paused_from_phase == :waiting_for_chisel
assert restored.pending_action == pending_action
assert Repo.aggregate(CommandRecord, :count) == command_count
assert Repo.get_by!(GameEvent, game_id: game.id, event_type: "game_paused").sequence > 0
~~~

Assert exactly one game_paused row and one snapshot at paused_version. Call
pause again and assert version and row counts remain unchanged.

- [ ] **Step 2: Verify red**

Run: rtk mix test test/detective/games/runtime_test.exs

Expected: Session.pause_for_disconnect/2 is missing.

- [ ] **Step 3: Add transactional system persistence**

Add game_paused/game_resumed to persisted event mappings. Implement:

~~~elixir
def persist_system_transition(
      game_id,
      expected_version,
      transition_id,
      %State{} = next_state,
      events,
      expected_status
    )
~~~

The Ecto.Multi locks the game row, requires expected_version and expected_status,
inserts events under transition_id, inserts the snapshot, and updates status,
phase, and version. It must not insert a game_commands row.

Allow normal command persistence only for active gameplay or paused resume:

~~~elixir
defp command_status_valid?("active", type) when type != :resume_game, do: true
defp command_status_valid?("paused", :resume_game), do: true
defp command_status_valid?(_status, _type), do: false
~~~

- [ ] **Step 4: Add serialized session pause**

~~~elixir
def pause_for_disconnect(game_id, player_ids) do
  session_call(game_id, {:pause_for_disconnect, player_ids}, 15_000, 1)
end
~~~

The handler runs Engine.apply_system/2. Empty events return the unchanged state
without persistence. A changed transition generates one UUID, persists against
state.version and "active", attaches delivery metadata, and swaps GenServer
state only after commit.

Add a non-blocking monitor entry point:

~~~elixir
def request_pause_for_disconnect(game_id, player_ids) do
  with {:ok, pid} <- SessionSupervisor.ensure_session(game_id) do
    GenServer.cast(pid, {:pause_for_disconnect, player_ids})
    :ok
  end
end
~~~

The cast handler uses the same private transition helper as the synchronous
test API and calls GameBroadcaster.broadcast/2 only after persistence succeeds.
This prevents a Session-to-Monitor resume check from deadlocking against a
Monitor-to-Session pause request.

- [ ] **Step 5: Register broadcaster names**

Add:

~~~elixir
game_paused: "game_paused",
game_resumed: "game_resumed"
~~~

- [ ] **Step 6: Run, format, commit**

Run: rtk mix test test/detective/games/runtime_test.exs

Run: rtk mix format

Commit:

~~~text
feat(game): persist disconnect pauses
~~~

---

### Task 4: Add the Presence-backed connection monitor

**Files:**
- Create: lib/detective/games/connection_monitor.ex
- Create: lib/detective/games/connection_monitor_supervisor.ex
- Create: test/detective/games/connection_monitor_test.exs
- Modify: lib/detective/application.ex
- Modify: lib/detective/games/session.ex
- Modify: lib/detective/games/command.ex
- Modify: config/config.exs
- Modify: config/runtime.exs
- Modify: config/test.exs

**Interfaces:**
- Produces: ConnectionMonitor.ensure_monitor(game_id, player_ids, game_status).
- Produces: ConnectionMonitor.presence_topic(game_id).
- Produces: ConnectionMonitor.sync(game_id), connection_state(game_id), and all_players_online?(game_id).
- Produces: ConnectionMonitor.game_status_changed(game_id, status).
- Consumes: Session.request_pause_for_disconnect/2 on valid expiry.

- [ ] **Step 1: Write failing process tests**

Use real DetectiveWeb.Presence entries and holder processes started with
start_supervised!/1. Cover two tabs, reconnect cancellation, stale timer token,
two simultaneous offline players yielding one pause, and monitor restart.

Core assertion:

~~~elixir
first_tab = start_presence_holder(game_id, player_id)
second_tab = start_presence_holder(game_id, player_id)
{:ok, _pid} = ConnectionMonitor.ensure_monitor(game_id, player_ids, :active)

stop_presence_holder(first_tab)
assert %{online_player_ids: online} = ConnectionMonitor.sync(game_id)
assert player_id in online

stop_presence_holder(second_tab)
assert %{offline_deadlines: deadlines} = ConnectionMonitor.sync(game_id)
assert is_integer(deadlines[player_id])
~~~

Use these deterministic timeout assertions after reading the monitor state with
:sys.get_state/1:

~~~elixir
monitor_state = :sys.get_state(monitor_pid)
timer = monitor_state.timers[player_id]

# Reconnect cancels the live timer.
returned_tab = start_presence_holder(game_id, player_id)
_ = ConnectionMonitor.sync(game_id)
send(monitor_pid, {:disconnect_timeout, player_id, timer.token})
refute_receive %Phoenix.Socket.Broadcast{event: "game_paused"}

# An unrelated token is always stale.
stop_presence_holder(returned_tab)
_ = ConnectionMonitor.sync(game_id)
send(monitor_pid, {:disconnect_timeout, player_id, make_ref()})
refute_receive %Phoenix.Socket.Broadcast{event: "game_paused"}
~~~

For two expired players, subscribe to game:<game_id>, send both current timer
messages, and assert exactly one authoritative transition:

~~~elixir
DetectiveWeb.Endpoint.subscribe("game:#{game_id}")
state = :sys.get_state(monitor_pid)

Enum.each([first_player_id, second_player_id], fn id ->
  send(monitor_pid, {:disconnect_timeout, id, state.timers[id].token})
end)

assert_receive %Phoenix.Socket.Broadcast{event: "game_paused"}
refute_receive %Phoenix.Socket.Broadcast{event: "game_paused"}
assert {:ok, paused} = Session.get_state(game_id)
assert paused.status == :paused
~~~

Terminate the supervised monitor with Process.monitor/1, start it again through
ensure_monitor/3, call sync/1, and assert the live Presence holder is online
while absent members have fresh deadlines.

Use Presence broadcasts, Process.monitor/1, assert_receive, and :sys.get_state/1;
never Process.sleep/1.

Define the holder helpers in ConnectionMonitorTest:

~~~elixir
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
  pid
end

defp stop_presence_holder(pid) do
  monitor = Process.monitor(pid)
  send(pid, :stop)
  assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
end
~~~

- [ ] **Step 2: Verify red**

Run: rtk mix test test/detective/games/connection_monitor_test.exs

Expected: monitor modules are missing.

- [ ] **Step 3: Add configuration**

In config/config.exs:

~~~elixir
config :detective, :disconnect_grace_ms, 180_000
~~~

Set 50 in test.exs. In the dev-only runtime branch, parse
GAME_DISCONNECT_GRACE_MS for Playwright. Do not accept that override in
production.

~~~elixir
if config_env() == :dev do
  case Integer.parse(System.get_env("GAME_DISCONNECT_GRACE_MS", "")) do
    {milliseconds, ""} when milliseconds > 0 ->
      config :detective, :disconnect_grace_ms, milliseconds

    _other ->
      :ok
  end
end
~~~

- [ ] **Step 4: Implement supervisor and monitor**

Register the process at {:connection_monitor, game_id}. State:

~~~elixir
%{
  game_id: game_id,
  player_ids: MapSet.new(player_ids),
  game_status: :active,
  timers: %{
    player_id => %{
      token: reference,
      timer_ref: reference,
      deadline_unix_ms: integer
    }
  }
}
~~~

sync/1 re-reads Presence.list/1 rather than trusting diff order. It cancels
timers for returned players, creates one timer per newly absent player, and
broadcasts only:

~~~elixir
%{
  online_player_ids: Enum.sort(online_ids),
  offline_deadlines: deadline_map,
  all_players_online: MapSet.equal?(online_ids, state.player_ids)
}
~~~

init/1 subscribes to the internal Presence topic. handle_info/2 handles
presence_diff by calling the same reconcile function as sync/1.
all_players_online?/1 also reconciles from Presence before answering, so a
Resume command cannot observe stale cached data.

Schedule deadlines only while game_status is :active. A successful pause calls
game_status_changed(game_id, :paused), which cancels every timer but continues
online tracking. A successful resume switches back to :active. A finished state
cancels timers and stops the monitor normally.

On timeout, verify token, re-read Presence, and call the non-blocking
Session.request_pause_for_disconnect/2 with all currently offline players.
GameSession owns persistence and authoritative broadcasts.

- [ ] **Step 5: Supervise monitors**

Add ConnectionMonitorSupervisor after SessionSupervisor in
Detective.Application. Its ensure path must handle already_started races like
SessionSupervisor.ensure_session/1.

- [ ] **Step 6: Gate resume in GameSession**

For a new :resume_game command:

~~~elixir
defp validate_connection_gate(state, %Command{type: :resume_game}) do
  with {:ok, _pid} <-
         ConnectionMonitor.ensure_monitor(
           state.game_id,
           Map.keys(state.players),
           state.status
         ),
       true <- ConnectionMonitor.all_players_online?(state.game_id) do
    :ok
  else
    _reason -> {:error, :players_offline}
  end
end

defp validate_connection_gate(_state, _command), do: :ok
~~~

Run the gate after duplicate-command lookup. Only now add
command_type("resume_game"). After every committed transition, notify the
monitor with game_status_changed/2; this covers pause, resume, and finish
without relying on client broadcasts.

- [ ] **Step 7: Run, format, commit**

Run: rtk mix test test/detective/games/connection_monitor_test.exs test/detective/games/engine_test.exs test/detective/games/runtime_test.exs

Run: rtk mix format

Commit:

~~~text
feat(game): monitor player connections
~~~

---

### Task 5: Track game Presence and allow paused rejoins

**Files:**
- Modify: lib/detective/games.ex
- Modify: lib/detective_web/channels/game_channel.ex
- Modify: test/detective_web/channels/game_channel_test.exs
- Modify: test/detective_web/live/game_live_test.exs

**Interfaces:**
- Consumes: ConnectionMonitor APIs.
- Produces: authorized tracking on game_presence:<game_id>.
- Produces: sanitized connection_state messages.
- Produces: member access for active and paused games.

- [ ] **Step 1: Write failing web tests**

Join two game channels as the same Detective. Leaving one keeps the player
online; leaving the second creates a deadline. Assert payload keys exactly:

~~~elixir
assert_broadcast "connection_state", payload
assert Enum.sort(Map.keys(payload)) ==
         [:all_players_online, :offline_deadlines, :online_player_ids]
refute Jason.encode!(payload) =~ "solution"
refute Jason.encode!(payload) =~ "response_matrix"
~~~

Persist a paused state in GameLiveTest and assert the active member still
renders #game-book-frontend. Waiting games and outsiders still redirect.

~~~elixir
{:ok, state} = Session.get_state(game.id)
detective_player = State.player_by_user_id(state, detective.id)

assert {:ok, _reply} =
         Session.pause_for_disconnect(game.id, [detective_player.id])

assert {:ok, view, _html} =
         conn
         |> log_in_user(detective)
         |> live(~p"/games/#{game.id}")

assert has_element?(view, "#game-book-frontend")
~~~

Add a paused ChannelTest that starts with both member channels connected and
asserts the paused, role, and online gates:

~~~elixir
detective_resume =
  push(detective_game_socket, "command", %{
    "command_id" => Ecto.UUID.generate(),
    "type" => "resume_game",
    "expected_version" => paused_version,
    "payload" => %{}
  })

assert_reply detective_resume, :error, %{code: "wrong_role"}

paused_action =
  push(detective_game_socket, "command", %{
    "command_id" => Ecto.UUID.generate(),
    "type" => "end_turn",
    "expected_version" => paused_version,
    "payload" => %{}
  })

assert_reply paused_action, :error, %{code: "game_paused"}

leave(detective_game_socket)
host_resume = push(host_game_socket, "command", resume_payload(paused_version))
assert_reply host_resume, :error, %{code: "players_offline"}

assert {:ok, _reply, _rejoined_detective} =
         subscribe_and_join(
           authenticated_socket(detective),
           "game:#{game.id}",
           %{}
         )

host_resume = push(host_game_socket, "command", resume_payload(paused_version))
assert_reply host_resume, :ok, %{version: resumed_version}
assert_broadcast "game_resumed", %{version: ^resumed_version}
~~~

Define the test helper in GameChannelTest:

~~~elixir
defp resume_payload(version) do
  %{
    "command_id" => Ecto.UUID.generate(),
    "type" => "resume_game",
    "expected_version" => version,
    "payload" => %{}
  }
end
~~~

- [ ] **Step 2: Verify red**

Run: rtk mix test test/detective_web/channels/game_channel_test.exs test/detective_web/live/game_live_test.exs

- [ ] **Step 3: Allow paused projections**

Replace active-only validation:

~~~elixir
defp validate_playable_game(%{status: status}) when status in ["active", "paused"],
  do: :ok

defp validate_playable_game(_lobby), do: {:error, :game_not_active}
~~~

Do not move or add routes.

- [ ] **Step 4: Track Presence after authorized join**

Assign player_id and all player IDs in join/3, then send :after_join:

~~~elixir
socket =
  socket
  |> assign(:game_id, projection.public.game_id)
  |> assign(:player_id, projection.private.player_id)
  |> assign(:game_player_ids, Enum.map(projection.public.players, & &1.id))
  |> assign(
    :game_status,
    if(projection.public.status == "paused", do: :paused, else: :active)
  )

send(self(), :after_join)
{:ok, %{state: projection.public}, socket}
~~~

In handle_info, ensure the monitor first:

~~~elixir
{:ok, _pid} =
  ConnectionMonitor.ensure_monitor(
    socket.assigns.game_id,
    socket.assigns.game_player_ids,
    socket.assigns.game_status
  )

{:ok, _ref} =
  Presence.track(
    self(),
    ConnectionMonitor.presence_topic(socket.assigns.game_id),
    socket.assigns.player_id,
    %{online_at: System.system_time(:second)}
  )

_state = ConnectionMonitor.sync(socket.assigns.game_id)
{:noreply, socket}
~~~

Presence monitors the Channel PID, so do not add custom terminate cleanup.
Allow game_paused, game_not_paused, and players_offline error codes.

- [ ] **Step 5: Run, format, commit**

Run: rtk mix test test/detective_web/channels/game_channel_test.exs test/detective_web/live/game_live_test.exs

Run: rtk mix format

Commit:

~~~text
feat(game): track realtime presence
~~~

---

### Task 6: Build the graphical pause interface

**Files:**
- Modify: assets/svelte/GameBook.svelte
- Modify: assets/css/app.css

**Interfaces:**
- Consumes: connection_state, public pause, game_paused, game_resumed, and available_actions.
- Produces: #game-pause-seal, #action-resume-game, player connection marks, and accessible countdown.

- [ ] **Step 1: Add client telemetry**

~~~javascript
let onlinePlayerIds = $state([])
let offlineDeadlines = $state({})
let allPlayersOnline = $state(false)
let connectionSnapshotReceived = $state(false)
let connectionClock = $state(Date.now())

let offlinePlayers = $derived(
  connectionSnapshotReceived
    ? publicState.players.filter((player) => !onlinePlayerIds.includes(player.id))
    : [],
)
~~~

Handle:

~~~javascript
gameChannel.on("connection_state", (state) => {
  onlinePlayerIds = state.online_player_ids
  offlineDeadlines = state.offline_deadlines
  allPlayersOnline = state.all_players_online
  connectionSnapshotReceived = true
})
~~~

Run one 1-second interval inside existing onMount and clear it in cleanup.
Format positive remaining time as MM:SS; display PAUSED after expiry. Never
change publicState from the local clock.

- [ ] **Step 2: Handle events and errors**

Record game_paused/game_resumed in the public activity line. Extend errors:

~~~javascript
game_paused: "The case is sealed while a player is offline.",
game_not_paused: "The case is not paused.",
players_offline: "Every player must reconnect before the Chisel resumes.",
~~~

game_state remains the only source changing public status/phase.

- [ ] **Step 3: Mark offline bookmarks**

~~~svelte
{#if !onlinePlayerIds.includes(detective.id)}
  <span id={"detective-connection-" + seat} class="detective-offline-mark">
    OFFLINE · {disconnectCountdown(detective.id)}
  </span>
{/if}
~~~

Add matching #chisel-connection-state output in the existing Chisel area.

~~~svelte
<span
  id="chisel-connection-state"
  class={onlinePlayerIds.includes(chisel.id) ? "text-[#315344]" : "text-[#973b32]"}
>
  {onlinePlayerIds.includes(chisel.id)
    ? "ONLINE"
    : "OFFLINE · " + disconnectCountdown(chisel.id)}
</span>
~~~

- [ ] **Step 4: Add the case-seal overlay**

Place it as the final child of #open-casebook:

~~~svelte
{#if publicState.status === "paused"}
  <section
    id="game-pause-seal"
    class="game-pause-seal"
    role="status"
    aria-labelledby="game-pause-heading"
  >
    <div class="game-pause-document">
      <p class="font-mono text-[10px] uppercase tracking-[0.2em]">Case sealed</p>
      <h2 id="game-pause-heading" class="mt-2 font-serif text-3xl font-semibold">
        Investigation paused
      </h2>
      <p class="mt-3 font-serif italic">
        Waiting for every investigator to return.
      </p>

      {#if privateState.role === "chisel"}
        <button
          id="action-resume-game"
          type="button"
          disabled={!allPlayersOnline || !availableActions.has("resume_game") || commandPending}
          onclick={() => sendCommand("resume_game", {})}
        >Resume investigation</button>
      {/if}
    </div>
  </section>
{/if}
~~~

The overlay intercepts pointer input while the SVG and pending workspace remain
mounted.

- [ ] **Step 5: Add raw CSS**

Add a dark scrim, paper document, red stamped border, visible focus state,
disabled Resume state, and short seal-in animation. Reuse IBM Plex variables.
The existing prefers-reduced-motion rule under #game-book-shell must reduce the
new animation.

~~~css
.game-pause-seal {
  position: absolute;
  inset: 0;
  z-index: 60;
  display: grid;
  place-items: center;
  padding: 1.5rem;
  background: rgb(24 17 13 / 0.78);
  backdrop-filter: blur(2px);
}

.game-pause-document {
  width: min(34rem, 100%);
  border: 3px double #8f372f;
  background: #e7d8b9;
  padding: clamp(1.5rem, 4vw, 3rem);
  color: #2c2119;
  box-shadow: 0 24px 70px rgb(0 0 0 / 0.5);
  animation: game-pause-seal-in 320ms cubic-bezier(0.22, 0.72, 0.24, 1) both;
}

.game-pause-document button {
  margin-top: 1.25rem;
  min-height: 3rem;
  width: 100%;
  cursor: pointer;
  border: 1px solid #6f2f29;
  background: #8f372f;
  color: #fff0d6;
  font-family: "IBM Plex Sans", ui-sans-serif, system-ui, sans-serif;
  font-weight: 600;
  transition: background-color 160ms ease, transform 160ms ease;
}

.game-pause-document button:hover:not(:disabled) {
  background: #a84338;
  transform: translateY(-1px);
}

.game-pause-document button:focus-visible {
  outline: 3px solid #f1d7a5;
  outline-offset: 3px;
}

.game-pause-document button:disabled {
  cursor: not-allowed;
  opacity: 0.45;
}

@keyframes game-pause-seal-in {
  from { opacity: 0; transform: translateY(12px) rotate(-0.5deg); }
  to { opacity: 1; transform: translateY(0) rotate(0); }
}
~~~

- [ ] **Step 6: Build and commit**

Run: rtk mix assets.build

Expected: Vite/Svelte and Tailwind pass.

Commit:

~~~text
feat(ui): add paused case seal
~~~

---

### Task 7: Verify the complete reconnect slice

**Files:**
- Modify only files required by failures found during verification.
- Add no new production scope.

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces: verified two-browser pause/resume flow and a green project gate.

- [ ] **Step 1: Run focused regressions**

Run: rtk mix test test/detective/games test/detective_web/channels test/detective_web/live/game_live_test.exs

Expected: pass.

- [ ] **Step 2: Start a QA server**

Run: rtk env GAME_DISCONNECT_GRACE_MS=1500 mix phx.server

Use a PTY session. Production/default remains 180_000 milliseconds.

- [ ] **Step 3: Run Playwright two-context acceptance**

Use independent chisel and detective sessions:

1. Join the same active game and receive online marks.
2. Reload Detective within 1.5 seconds; version stays unchanged and no seal appears.
3. Disconnect Detective through expiry; Chisel sees countdown, then #game-pause-seal and one new version.
4. Verify gameplay while paused returns game_paused.
5. Reconnect Detective; only Chisel gets enabled #action-resume-game.
6. Resume and restore the exact pre-pause phase.
7. Pause during interrogation, resume, and complete the next legal response.
8. Check 1440x1000 and 390x844 with zero console errors.

- [ ] **Step 4: Run full project gate**

Run: rtk mix precommit

Expected: formatter, compiler, tests, and assets pass.

- [ ] **Step 5: Inspect scope**

Run: rtk git status --short

Run: rtk git diff --check

Confirm .agents/, output/, and skills-lock.json remain untracked and unstaged.
Confirm connection_state contains no game secrets.

- [ ] **Step 6: Commit only verification fixes**

If tracked fixes were required:

~~~text
fix(game): stabilize reconnect flow
~~~

If no tracked fixes exist, create no empty commit.
