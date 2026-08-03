# Game Reconnect and Pause Design

## Scope

This spec covers slice A only: authoritative connection tracking, a 180-second
disconnect grace period, persisted game pause, reconnect synchronization, and
Chisel-controlled resume. Multiplayer browser acceptance and further graphical
polish remain separate slices B and C.

The game page stays in the existing authenticated router scope and
`live_session :require_authenticated_user`. No route changes are required.

## Goals

- Treat a player as online while at least one of their game tabs is connected.
- Give every disconnected player 180 seconds to reconnect without changing
  authoritative game state or version.
- Pause exactly once if any active player remains offline when their deadline
  expires.
- Persist pause and resume through the normal game snapshot and event model.
- Restore the exact gameplay phase and pending action after the Chisel resumes.
- Keep connection telemetry public and free of case secrets.

## Non-goals

- Automatic game resume.
- Removing or replacing disconnected players.
- Host migration or assigning a new Chisel.
- Continuing gameplay while any active member is offline.
- Cross-node Presence coordination beyond the current single-node MVP.

## Architecture

### Presence tracking

`DetectiveWeb.GameChannel` starts or finds the monitor for its game after an
authorized join, then tracks its channel process with `DetectiveWeb.Presence`.
Presence uses an internal `game_presence:<game_id>` topic keyed by
`game_player_id`. Each browser tab produces a separate Presence meta, so closing
one tab does not mark the player offline while another meta remains.

The raw Presence topic is internal. Clients receive only a sanitized
`connection_state` message on `game:<game_id>`:

```text
online_player_ids
offline_deadlines
all_players_online
```

Player IDs are already public in the game projection. Connection messages must
not contain user IDs, response data, case content, notes, or other private
fields.

### Connection monitor

`Detective.Games.ConnectionMonitor` is one process per active or paused game.
It is started under `Detective.Games.ConnectionMonitorSupervisor` and registered
in `Detective.GameRegistry` with key `{:connection_monitor, game_id}`. Existing
game sessions keep their current registry keys.

The monitor subscribes to its internal Presence topic and derives online state
from `Presence.list/1`; it does not trust the contents or ordering of a single
diff. Its state contains one timer token and monotonic deadline per fully
offline player. The default grace period is `180_000` milliseconds and is
application-configurable for deterministic tests and browser QA.

When a player reconnects before the deadline, the monitor cancels that timer.
A stale timeout message must verify its token and current Presence state before
doing anything. Concurrent or duplicate timeout messages are therefore safe.

### Authoritative transitions

The monitor never edits game state. On a valid expiry it calls
`GameSession.pause_for_disconnect/2`. The session serializes this system
transition with player commands and invokes a pure engine transition. If the
game has already paused or finished, the transition is a no-op.

Pause persistence uses an `Ecto.Multi` transaction that locks the game row,
checks its current version and active status, inserts the public event and new
snapshot, and advances the game version. A system event has its own UUID command
identifier in `game_events`; it does not create a misleading user-owned row in
`game_commands`.

Resume remains an authenticated player command. Only the Chisel can send
`resume_game`. Before applying it, `GameSession` asks the monitor to confirm
that every active game member is online. The pure engine then restores the
saved phase, and normal command persistence records the Chisel actor,
`game_resumed` event, snapshot, status, phase, and version.

## State and Database Changes

`Detective.Games.State` gains:

```text
paused_from_phase
pause_reason
paused_player_ids
```

On pause:

- `status` becomes `:paused`.
- `phase` becomes `:paused`.
- `paused_from_phase` stores the exact prior phase.
- `pause_reason` becomes `:player_disconnected`.
- `paused_player_ids` captures every offline active player at transition time.
- Turn order, action points, `pending_action`, evidence, statements, secret
  response options, and histories remain unchanged.

On resume, status becomes `:active`, phase returns to `paused_from_phase`, and
the pause metadata is cleared. The snapshot schema version is incremented and
the codec explicitly encodes and decodes these fields.

A migration extends the games status constraint to allow `paused`. The Game
schema and projection lookup accept both active and paused games as playable;
waiting, finished, and cancelled games remain rejected by the game page.

## Realtime Flow

```text
last tab leaves
  -> Presence diff
  -> monitor reads full Presence state
  -> broadcast connection_state with deadline
  -> start 180-second timer

reconnect before deadline
  -> monitor reads Presence state
  -> cancel timer
  -> broadcast connection_state
  -> no game version change

deadline expires while still offline
  -> GameSession system transition
  -> engine creates paused state and game_paused event
  -> transaction stores event + snapshot + version
  -> broadcaster sends authoritative projections

all players reconnect
  -> connection_state reports all_players_online
  -> Chisel sends resume_game
  -> server rechecks Presence
  -> engine restores previous phase
  -> transaction stores game_resumed + snapshot + version
```

Joining a paused game is allowed for active members. The join reply contains
the latest public projection; the private user topic supplies the corresponding
private projection. This makes reload and process restart converge on database
state rather than client memory.

## Command and Event Contract

New user command:

```json
{
  "command_id": "UUID",
  "type": "resume_game",
  "expected_version": 23,
  "payload": {}
}
```

New persisted public events:

- `game_paused`: reason and disconnected public player IDs.
- `game_resumed`: resuming Chisel player ID and restored phase.

New ephemeral event:

- `connection_state`: online player IDs, offline deadlines, and
  `all_players_online`.

New command errors:

- `game_paused`: a gameplay command was attempted while paused.
- `game_not_paused`: resume was attempted from another state.
- `players_offline`: the Chisel attempted resume before every member returned.
- Existing `wrong_role`, `not_a_member`, `stale_version`, and authorization
  errors continue to apply.

## UI Behavior

`GameBook.svelte` keeps connection telemetry separate from public and private
game projections. Detective bookmarks show an `OFFLINE` mark and a countdown
derived from the server deadline. The client may animate the displayed timer,
but it never decides when the game pauses.

While paused, a full-board case-seal treatment blocks pointer gameplay without
destroying the underlying SVG or current selections. It displays the offline
players and pause reason. Detectives see a waiting message. The Chisel sees a
Resume control only when `all_players_online` is true; the server still repeats
that check. Motion respects `prefers-reduced-motion`.

The existing reconnect banner remains useful for the local user's transport
state. The case-seal UI represents authoritative game pause and is not replaced
by that banner.

## Failure Handling

- Presence diff reordering: always re-read the complete Presence list.
- Stale timeout: compare timer token and recheck Presence before pausing.
- Multiple expired players: the serialized session persists one pause only.
- Command racing with expiry: `GameSession` establishes the order; each accepted
  transition receives its own version.
- Monitor restart: reconstruct online state from Presence and schedule missing
  members from the restart time. A persisted paused game stays paused.
- Application restart with nobody connected: state remains safely persisted;
  the first authorized join starts the monitor and deadlines for missing
  members.
- Finished game: do not schedule timers and ignore late expiry messages.
- Resume with a missing monitor: ensure the monitor, rebuild Presence state,
  then reject with `players_offline` unless every member is present.

## Test Strategy

### Unit and process tests

- One tab leaves while another remains: no timer.
- Last tab leaves: one 180-second deadline is recorded.
- Reconnect before expiry: timer is cancelled and version is unchanged.
- Stale and duplicate timeout messages: no duplicate pause.
- Multiple offline players: only one authoritative pause.
- Monitor restart: Presence state is reconstructed.

Tests use configurable grace duration, direct process messages, monitors, and
`:sys.get_state/1`; they do not use `Process.sleep/1`.

### Engine and persistence tests

- Pause and resume from detective turn, every interrogation waiting phase, and
  accusation.
- Pending action and all public/private state survive the round trip.
- Non-Chisel resume and gameplay commands while paused are rejected.
- Resume while a member is offline is rejected before the engine transition.
- Paused snapshot restores after `GameSession` termination.
- Game row, event sequence, snapshot, and version remain consistent.

### Channel and security tests

- Only active members can join and create Presence entries.
- Multi-tab Presence semantics are preserved.
- Connection and pause broadcasts reach all game members.
- Connection payloads contain no secret fields.
- Paused members can rejoin; outsiders still cannot.

### Browser acceptance

Playwright uses independent Chisel and Detective contexts. The dev server runs
with a short grace override while the default remains 180 seconds. Acceptance
covers:

1. Reload under the grace period without pause or version change.
2. Disconnect through expiry and observe the countdown and persisted pause.
3. Reconnect all players and confirm only the Chisel can resume.
4. Resume an in-progress interrogation and complete its next command.
5. Check desktop and narrow viewport rendering with zero console errors.

The final verification command is `mix precommit`.

## Acceptance Criteria

- A player is online while any game tab remains connected.
- The configured production/default grace period is exactly 180 seconds.
- A reconnect within the grace period never changes the game version.
- An expired disconnect pauses once and survives reload and server restart.
- No gameplay command succeeds while paused.
- Only the Chisel can resume, and only after every active member is online.
- Resume restores the exact prior phase and pending action.
- No connection payload leaks private case or player information.
- Automated tests and two-context Playwright acceptance pass.
