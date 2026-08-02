# Vertical slice architecture

## Product boundary

Detective is an original, realtime investigation game inspired by asymmetric
deduction board games. It does not redistribute commercial casebooks, card
text, dialogue, artwork, audio, logos, or other trade dress.

The first playable slice is:

```text
register -> log in -> create room -> accept invite -> ready -> start
-> interrogate -> private response selection -> private answer
-> challenge -> persisted result
```

The mechanics were checked against the publisher's
[product overview](https://vanrydergames.com/collections/dcoa),
[rulebook](https://cdn.1j1ju.com/medias/83/d6/eb-detective-city-of-angels-rulebook.pdf),
and
[case-design guide](https://cdn.shopify.com/s/files/1/0593/6984/8897/files/DCOA_CaseDesignGuide_4aa8ffb0-787d-4f2d-b165-a50e972198c4.pdf?v=1717097104).
Only abstract mechanics are adapted. Every case, character, location, line of
dialogue, illustration, and visual identity in this application must be
original or separately licensed.

## Runtime decisions

- Phoenix is the only game authority.
- LiveView supplies authenticated page shells and initial role projections.
- LiveSvelte is the primary frontend.
- The board is an inline SVG scene with a stable `viewBox`.
- Authentication, forms, action controls, dialogs, and live announcements use
  semantic HTML. Graphics never replace keyboard or screen-reader access.
- Gameplay commands use a dedicated authenticated Phoenix socket. LiveView and
  Channels must not both process the same command.
- The browser stores projections, connection state, and presentation-only
  selection. It never owns game rules.
- The MVP runs on one BEAM node. A local `Registry` is not a distributed
  singleton guarantee.

```text
LiveSvelte SVG scene
        |
        | command_id + expected_version + payload
        v
GameChannel -> GameSession -> pure Engine -> Ecto.Multi
                                      |
                                      v
                  public / detective / chisel projections
```

## Information boundary

The public game topic announces public transitions only. An interrogation
answer is delivered only to the questioning detective and any explicitly
authorized observer. Response type, alternatives, solution, and hidden case
data are Chisel-only.

Projection modules construct allow-listed maps. They must never serialize the
state and delete secret keys afterward. Leakage tests inspect nested values as
well as top-level keys.

## Persistence model

`games.current_version` increments once per accepted command. Event sequence
increments once per emitted event. They are separate counters.

Commands and events are separate tables:

- `game_commands`: unique `game_id + command_id`; stores actor, type, payload
  digest, accepted version, and reply.
- `game_events`: unique `game_id + sequence`; one command may emit many events.
- `game_private_events`: event recipient and private payload.
- `game_snapshots`: unique `game_id + version`; includes a schema version.

An accepted command follows this order:

1. Authenticate actor from the socket, never from the payload.
2. Return the stored result for an identical duplicate command.
3. Validate expected version, membership, role, phase, and payload.
4. Run the pure engine to produce the next state and events.
5. Lock and verify the game row inside an `Ecto.Multi` transaction.
6. Persist command, events, snapshot, phase, status, and version.
7. After commit, replace in-memory state and broadcast projections.

Joining or detecting a version gap always triggers a fresh projection. This
recovers from a crash after commit but before broadcast without weakening the
database as the source of truth.

## Delivery gates

1. Accounts: generated Phoenix authentication, `display_name`, real
   `current_scope`, protected dashboard, revocable session-backed socket auth.
2. Rooms: original published sample case, game creation, one Chisel, hashed
   invite tokens, transactional capacity enforcement.
3. Lobby: membership-authorized socket, ready state, Presence telemetry, start
   validation, multi-tab aware disconnect handling.
4. Engine: pure interrogation, response selection, challenge, and phase tests.
5. Runtime: Registry, DynamicSupervisor, one session per local game, snapshots,
   idempotency, restore tests.
6. Realtime: public game topic, private user topic, leakage tests, reconnect.
7. Acceptance: two independent browser sessions complete the entire slice and
   retain state after reload and session restart.

Map movement, search, evidence economy, turn rotation, accusation, and advanced
animation start only after this slice passes `mix precommit` and browser QA.
