# Reconnect Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the three deferred reconnect findings before expanding map and action gameplay.

**Architecture:** Preserve the existing server-authoritative command pipeline and public payloads. Reorder only the pure Resume validation boundary, fold paused games into the existing active dashboard bucket, and invalidate browser Presence telemetry on local game-channel transport loss until a fresh server snapshot arrives.

**Tech Stack:** Elixir, Phoenix 1.8, Ecto, Phoenix Channels, LiveSvelte, Svelte 5, Vite 8, ExUnit, Playwright CLI.

## Global Constraints

- Change no routes, schemas, game phases, command payloads, or public Presence payload fields.
- Keep game routes inside the existing `live_session :require_authenticated_user`.
- Keep duplicate-command lookup before all new-command validation and Presence checks.
- Keep the server as the only authority for pause, Resume, version, role, and game state.
- Add no npm, Hex, browser, animation, or test-framework dependencies.
- Keep Tailwind v4 imports unchanged; use no DaisyUI, `@apply`, inline scripts, or external assets.
- Prefix every shell command with `rtk`; use `apply_patch` for source edits.
- Stage only task files. Preserve `.agents/`, `output/`, and `skills-lock.json` as unrelated untracked paths.
- Run `rtk mix precommit` after all three tasks and fix every new issue.

---

### Task 1: Validate Resume before Presence

**Files:**
- Modify: `lib/detective/games/session.ex:111-126`
- Test: `test/detective/games/connection_monitor_test.exs`

**Interfaces:**
- Consumes: `Engine.apply(State.t(), actor_id, Command.t())` and the existing `validate_connection_gate/2`.
- Produces: new-command error precedence `game_not_paused`, then `wrong_role`, then `players_offline` for an otherwise-valid Chisel Resume.

- [ ] **Step 1: Add a failing Session-level precedence test**

Add one test beside the existing Resume Presence test. Use the existing `active_game/0` helper so no player has Presence metadata:

```elixir
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
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
rtk mix test test/detective/games/connection_monitor_test.exs
```

Expected: the new test fails because the active or Detective Resume returns
`players_offline`, proving the external gate currently masks the pure engine
error. Use the printed `file:line` for subsequent single-test runs.

- [ ] **Step 3: Reorder the pure engine and Presence checks**

Change only `execute_new_command/3` so `Engine.apply/3` validates and computes the pure transition before `validate_connection_gate/2`:

```elixir
defp execute_new_command(state, actor_id, command) do
  with {:ok, next_state, events} <- Engine.apply(state, actor_id, command),
       :ok <- validate_connection_gate(state, command),
       {:ok, changes} <-
         Persistence.persist_command(state.game_id, actor_id, command, next_state, events) do
    events = Persistence.attach_delivery_metadata(events, changes, next_state.version)

    :ok =
      ConnectionMonitor.game_status_changed(
        state.game_id,
        next_state.status,
        next_state.version
      )

    reply = %{
      version: next_state.version,
      duplicate: false,
      events: events,
      state: next_state
    }

    {:reply, {:ok, reply}, next_state}
  else
    {:error, reason} -> {:reply, {:error, reason}, state}
  end
end
```

Do not persist or broadcast the computed transition until the Presence gate passes. Do not move duplicate lookup from `handle_call/3`.

- [ ] **Step 4: Run focused GREEN tests**

Run:

```bash
rtk mix test test/detective/games/connection_monitor_test.exs test/detective/games/runtime_test.exs test/detective_web/channels/game_channel_test.exs
```

Expected: all pass, including duplicate Resume replay and offline Chisel Resume.

- [ ] **Step 5: Commit Task 1**

```bash
rtk git add lib/detective/games/session.ex test/detective/games/connection_monitor_test.exs
rtk git diff --cached --check
rtk git commit -m "fix(game): validate resume before presence"
```

---

### Task 2: Count paused games as active

**Files:**
- Modify: `lib/detective/games.ex:122-138`
- Test: `test/detective/games_test.exs`

**Interfaces:**
- Consumes: persisted game statuses `waiting`, `active`, `paused`, and `finished` for the scoped active membership query.
- Produces: unchanged summary shape `%{waiting: non_neg_integer(), active: non_neg_integer(), finished: non_neg_integer()}` with `active` equal to active plus paused.

- [ ] **Step 1: Add a failing context test**

Add this test to `Detective.GamesTest`:

```elixir
test "counts paused games in the active dashboard bucket" do
  user = user_fixture()
  %{game: game} = game_fixture(user)

  game
  |> Ecto.Changeset.change(status: "paused")
  |> Repo.update!()

  assert Games.game_summary(Scope.for_user(user)) == %{
           waiting: 0,
           active: 1,
           finished: 0
         }
end
```

- [ ] **Step 2: Run the test and verify RED**

Run the exact printed test line:

```bash
rtk mix test test/detective/games_test.exs
```

Expected: `active` is `0`, proving the paused bucket is dropped.

- [ ] **Step 3: Fold paused into active without changing the map shape**

Keep the grouped query. Change only the final projection:

```elixir
%{
  waiting: Map.get(counts, "waiting", 0),
  active: Map.get(counts, "active", 0) + Map.get(counts, "paused", 0),
  finished: Map.get(counts, "finished", 0)
}
```

Do not add a `paused` key to the public dashboard props.

- [ ] **Step 4: Run context and dashboard GREEN tests**

Run:

```bash
rtk mix test test/detective/games_test.exs test/detective_web/live/dashboard_live_test.exs
```

Expected: all pass, including the unchanged empty dashboard shape.

- [ ] **Step 5: Commit Task 2**

```bash
rtk git add lib/detective/games.ex test/detective/games_test.exs
rtk git diff --cached --check
rtk git commit -m "fix(dashboard): count paused games active"
```

---

### Task 3: Invalidate stale browser connection telemetry

**Files:**
- Modify: `assets/svelte/GameBook.svelte:397-425,554-584`
- No new JS test framework or production module.

**Interfaces:**
- Consumes: Phoenix Channel callbacks `onError`, `onClose`, and the existing `connection_state` payload.
- Produces: a local invalidation function that clears browser telemetry; only a fresh `connection_state` marks the snapshot received again.

- [ ] **Step 1: Reproduce stale telemetry in a real browser (RED)**

Start the normal dev stack and use two independent Playwright CLI sessions. Reach a paused game where all players are connected and Chisel `#action-resume-game` is enabled. In the Chisel session run:

```javascript
window.getGameSocket().disconnect()
```

After the game channel reports its error/close, inspect:

```javascript
document.querySelector("#action-resume-game")?.disabled
```

Expected RED: Resume remains enabled from the stale `allPlayersOnline` snapshot.

- [ ] **Step 2: Add one telemetry invalidation function**

Inside `GameBook.svelte`, add:

```javascript
function invalidateConnectionSnapshot() {
  connectionState = "offline"
  connectionSnapshotReceived = false
  onlinePlayerIds = []
  offlineDeadlines = {}
  allPlayersOnline = false
}
```

Register it after creating the game channel:

```javascript
gameChannel.onError(invalidateConnectionSnapshot)
gameChannel.onClose(invalidateConnectionSnapshot)
```

Update the existing `connection_state` callback so a fresh server snapshot also restores the transport label:

```javascript
gameChannel.on("connection_state", (state) => {
  onlinePlayerIds = state.online_player_ids
  offlineDeadlines = state.offline_deadlines
  allPlayersOnline = state.all_players_online
  connectionSnapshotReceived = true
  connectionState = "online"
})
```

Do not mutate `publicState`, phase, status, version, private actions, or server deadlines locally.

- [ ] **Step 3: Build assets and verify the prior warning stays absent**

Run:

```bash
rtk mix assets.build
```

Expected: client and SSR builds pass; output contains no `node:async_hooks` warning.

- [ ] **Step 4: Verify browser GREEN and reconnect restoration**

Repeat the Chisel socket disconnect. Expected while disconnected:

- `#action-resume-game` exists but is disabled.
- The case seal remains controlled by authoritative paused public state.
- The mounted workspace remains inert.

Reconnect with:

```javascript
window.getGameSocket().connect()
```

Wait for a fresh `connection_state`. Expected:

- Chisel Resume becomes enabled only after every player is online.
- Detective still has no `#action-resume-game`.
- Desktop `1440x1000` and mobile `390x844` have no horizontal overflow.
- Fresh sessions report zero application console errors.

- [ ] **Step 5: Commit Task 3**

```bash
rtk git add assets/svelte/GameBook.svelte
rtk git diff --cached --check
rtk git commit -m "fix(ui): clear stale connection telemetry"
```

- [ ] **Step 6: Run the complete project gate**

Run:

```bash
rtk mix precommit
rtk git diff --check
rtk git status --short
```

Expected: client and SSR build pass without `node:async_hooks`; all ExUnit tests pass; only `.agents/`, `output/`, and `skills-lock.json` remain untracked.
