# Reconnect Polish Design

## Goal

Close the three non-blocking reconnect findings before expanding the game map
and action system. The slice corrects Resume error precedence, keeps paused
games visible in the dashboard's active count, and prevents stale client
connection telemetry from enabling Resume during a local transport outage.

## Scope

This slice changes no routes, schemas, game phases, command payloads, or public
Presence payload fields. Game routes remain in the existing authenticated
`live_session :require_authenticated_user`.

### Resume error precedence

`Session` keeps duplicate-command lookup first. For a new command, the pure
engine validates the actor, status, role, phase, version, and command before
the external Presence gate runs. A Resume sent while the game is active returns
`game_not_paused`; a Detective Resume returns `wrong_role`. Only an otherwise
valid Chisel Resume asks `ConnectionMonitor` whether every player is online.
If anyone is absent, it returns `players_offline`. The computed pure transition
is discarded until the Presence gate passes, so no state or event is persisted
early.

### Dashboard paused count

`Games.game_summary/1` continues returning the existing `waiting`, `active`,
and `finished` keys. Its `active` value becomes the sum of persisted `active`
and `paused` games for the scoped user. This keeps a paused but playable case in
the existing dashboard bucket without adding a new card or changing the public
dashboard contract.

### Local transport telemetry

`GameBook` invalidates its connection snapshot when the game channel reports an
error or closes. Invalidation sets the transport label offline, clears online
player IDs and offline deadlines, and makes `allPlayersOnline` false. This
immediately disables Resume without changing authoritative public game state.

A successful channel join may restore the transport label, but only a fresh
`connection_state` event marks the snapshot received and repopulates Presence
telemetry. The server remains the final Resume authority.

## Error Handling

- Duplicate commands retain their stored reply even if current Presence has
  changed.
- Invalid Resume commands never query Presence.
- Transport loss never locally pauses or resumes the game.
- Rejoin without a fresh connection snapshot keeps Resume disabled.

## Verification

- Unit tests cover active-game and Detective Resume precedence while players
  are offline.
- Context tests cover paused games contributing to the active dashboard count.
- Browser QA drops and restores the local game channel, verifying stale
  telemetry is cleared and only a fresh snapshot reenables Chisel Resume.
- `mix assets.build` emits no `node:async_hooks` warning.
- `mix precommit` passes before completion.

## Commits

Each behavior remains independently revertible:

1. `fix(game): validate resume before presence`
2. `fix(dashboard): count paused games active`
3. `fix(ui): clear stale connection telemetry`
