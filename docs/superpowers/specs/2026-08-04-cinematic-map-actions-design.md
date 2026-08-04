# Cinematic Map and Action System Design

## Status

Approved through the visual-companion and text design review on 2026-08-04.
The chosen direction is the C+ cinematic map HUD using the official
*Detective: City of Angels* board image for this public, non-commercial fan
project.

## Goal

Turn the existing game page into a graphics-first webgame board while keeping
Phoenix as the sole game authority. An active Detective can place or move by
clicking the map, every legal destination follows the Classic district rules,
and the same server-driven action model supports Search, Question, Analyze,
Kickback, End Turn, and Accuse.

The slice also replaces the fictional eight-location seed topology with the
canonical 100-location board catalog. A visually accurate board without the
matching server topology is not considered complete.

## Scope

- Use the official full-board artwork with the Case A-L slots, 100 numbered
  locations, district boundaries, and Day track.
- Add a canonical server-side catalog for the board's 100 locations.
- Enforce Classic player counts and starting-day defaults.
- Correctly gate placement and movement destinations in private projections.
- Split the oversized `GameBook.svelte` into focused graphics components.
- Implement click-select-confirm placement and movement.
- Render the four Detective HUD entries and the Chisel entry across the top.
- Drive the action dock and casebook drawer only from server projections.
- Add keyboard, reduced-motion, mobile, reconnect, authorization, and secret
  leakage coverage.

No new route is required. The game page remains in the existing authenticated
`live_session :require_authenticated_user`, behind the
`:require_authenticated_user` browser plug, because board state and private
player projections must never be available to anonymous visitors. The existing
LiveView continues passing `current_scope` into the game context.

## Non-goals

- Street-by-street routing, vehicles, pathfinding, or adjacency movement.
- Drag-and-drop movement.
- Sleuth-mode Stress rules.
- Head-to-head rule substitutions.
- AI, free-form questioning, spectator mode, or public matchmaking.
- Importing complete commercial cases or secret casebook content.
- Supporting case-specific map mutations in this slice.
- Changing Presence membership into game membership authority.

## Sources and Asset Policy

### Board artwork

The runtime board background is the publisher-hosted `GameBoard_FINAL` image:

```text
https://vanrydergames.com/cdn/shop/files/GameBoard_FINAL_069e54c3-3406-4bd3-9589-1fe30dee505f.png?v=1717096238
```

It is copied into the local asset tree rather than hotlinked. The source image
is preserved without painted-on application state. Player tokens, legal
destinations, selection state, district emphasis, pending commands, and motion
are separate SVG or HTML layers.

The official Case Design Kit's `City Planner/CityPlanner.pdf` is a calibration
reference for the 100 location coordinates and district borders:

```text
https://drive.google.com/file/d/1Pv9FxFB6w_93m9mgF3ZQ63KPVORO3X_w/view
```

The original 1932 K. M. Leuschner map remains available from the Library of
Congress and is retained as provenance:

```text
https://www.loc.gov/item/2006626011/
```

The project must add an adjacent `source.json` and a repository attribution
notice containing the publisher URL, original download URL, download date,
dimensions, checksum, copyright holder, and this statement:

```text
Unofficial public, non-commercial fan project. Not affiliated with or endorsed
by Van Ryder Games. Detective: City of Angels and its modified board artwork
belong to their respective rights holders.
```

Monetization is outside the approved scope. Commercialization requires written
permission or replacement of the publisher artwork with a separately licensed
composition.

### Rules

Classic rules are taken from the published rulebook and the publisher's Case
Design Guide:

```text
https://cdn.1j1ju.com/medias/83/d6/eb-detective-city-of-angels-rulebook.pdf
https://cdn.shopify.com/s/files/1/0593/6984/8897/files/DCOA_CaseDesignGuide_4aa8ffb0-787d-4f2d-b165-a50e972198c4.pdf?v=1717097104
```

Rule interpretations are recorded in unit tests. The UI never becomes a
second rules engine.

## Classic Rules Contract

### Players and starting day

- A production Classic game has exactly one Chisel and two to four Detectives.
- `start_game` rejects one-Detective rooms instead of silently applying the
  distinct head-to-head rules.
- The default starting Day is 9 with two Detectives, 8 with three Detectives,
  and 7 with four Detectives.
- A validated case-level starting-day override takes precedence over the
  default table.
- The top HUD reserves at most four Detective positions. The Chisel is always
  the rightmost entry.

### Detective turn

- A Detective begins a normal turn with four actions.
- Move, Search Location, Search Suspect, Question, Analyze, and Kickback are the
  action-producing commands in this slice.
- Actions may be repeated when their individual rule permits it.
- A Solve attempt is available only at the beginning of the Detective's turn,
  before spending actions.
- Analyze spends one action and grants one Scratch.
- Kickback is available once per Day at a Mob Joint and grants Scratch equal to
  the number of players.
- Bribes are not modeled as Detective actions: Goon and Detective cost two
  Scratch; Officer and Snitch cost three Scratch.

### Placement and movement

- An unplaced Detective must place at any Police Station when their first turn
  begins.
- Placement costs zero actions.
- A Move costs exactly one action.
- A Move may target any other board location sharing at least one district with
  the current location.
- A location on a district border belongs to every listed district and bridges
  movement between them.
- Street adjacency, travel distance, and the drawn road network do not affect
  legality or cost.
- A Detective with no actions remaining cannot Move.
- The Chisel never places or moves a token as a player action.

### Chisel timing

The Chisel has no independent turn and no Detective AP or Scratch display. The
Chisel reacts through private prompts, spends Detective-specific leverage when
permitted, and receives the pending response state through the private user
topic.

## Canonical Board Catalog

The board topology is server-owned static domain data, not Svelte constants.
Each of the 100 locations has a stable record shaped like:

```text
id                  stable string based on board number
number              integer 1..100
slug                readable stable slug
name                printed board name
type                standard | police_station | mob_joint
district_ids        one or more Classic district identifiers
x, y                normalized coordinates in board-image space
```

The five district identifiers are stable and independent of display copy:

```text
westside
hollywood
central_la
san_gabriel_valley
south_bay
```

The catalog loader rejects duplicate numbers, missing numbers, unknown
districts, empty district membership, invalid special-location types, and
coordinates outside `0.0..1.0`. Movement uses `district_ids`; image geometry is
presentation data only.

Case definitions reference catalog location IDs for suspects, searches, crime
scenes, and setup. They no longer redefine base district topology. The sample
case is remapped to suitable canonical locations. Case-specific map mutations
will require a separate design because they alter shared topology.

The public projection exposes only the board fields needed to draw the map and
public tokens. Search content, suspect secrets, and Chisel-only metadata remain
outside this catalog.

## Projection Contract

`Rules.available_actions/2` remains the canonical action query. The Detective
private projection derives destination lists from that result:

- `placement_location_ids` is non-empty only when `"place"` is present in
  `available_actions`.
- `valid_move_location_ids` is non-empty only when `"move"` is present in
  `available_actions`.
- Both lists are empty for the Chisel, inactive Detectives, paused games,
  non-Detective phases, and stale private state.
- `valid_move_location_ids` is also empty when the active Detective has no AP
  or must resolve a free Question before taking other actions.

This closes the current gap where movement destination IDs can be projected
even when `available_actions` does not permit movement. The browser must still
intersect destination IDs with `available_actions`; neither value authorizes a
command on its own.

The public projection continues exposing current player location and AP so
every participant can render the same authoritative token positions. Private
projections supply personal Scratch, leverage, evidence, permitted actions,
and role-specific prompts.

## UI Architecture

`GameBook.svelte` becomes an orchestration shell instead of owning the complete
board, HUD, dialogs, action controls, realtime transport, and animation logic.

### `GameBoard.svelte`

- Renders the official board image at its native aspect ratio.
- Owns the transparent SVG coordinate plane, location hotspots, public tokens,
  selection marker, and completed-move animation.
- Receives normalized locations and explicit legal IDs as props.
- Emits `select-location`; it never sends Phoenix commands.
- Makes only legal destinations keyboard-focusable and clickable.
- Exposes an HTML destination-list slot for non-visual navigation.

### `PlayerHUD.svelte`

- Renders up to four Detective dossiers followed by the Chisel dossier.
- Detective dossiers show portrait, AP, Scratch, leverage summary, location,
  online state, and active-turn state when visible to the current role.
- The Chisel dossier shows Chisel identity, online state, pending-response
  state, and Detective-specific leverage. It does not invent AP or Scratch.
- Uses original portrait assets or explicitly licensed/generated portraits;
  missing art falls back to a designed silhouette, not a broken image.

### `ActionDock.svelte`

- Renders only actions present in the current private projection.
- Owns the selected movement slip, confirmation control, pending-command state,
  and concise command errors.
- Keeps movement separate from Search, Question, Analyze, Kickback, End Turn,
  and Accuse controls.
- Never computes AP costs or command legality.

### `CasebookDrawer.svelte`

- Opens from the right for Search, Question, Evidence, Accusation, history, and
  role-specific private material.
- Shrinks the desktop map viewport instead of covering the selected location.
- Becomes a bottom sheet on narrow screens while leaving at least 55vh for the
  board.
- Retains the approved physical-book visual language: paper, tabs, stamps,
  restrained texture, and readable serif body typography.

### `GameBook.svelte`

- Owns public/private projection reconciliation and Phoenix channel commands.
- Converts component events into commands with `command_id` and
  `expected_version`.
- Applies authoritative projection updates after ACK/broadcast.
- Owns reconnect invalidation and rehydration.
- Does not contain raw board hotspot markup after the extraction.

## Visual Layout

The map fills the viewport and remains the dominant visual layer. The HUD forms
a compact top strip with D1-D4 from left to right and the Chisel fixed at the
far right. The bottom action dock floats above the board edge. The casebook
drawer occupies the right side only while needed.

Board furniture already present in the official image remains visible:

- Case slots A-L along the top.
- Day track 1-12 on the right.
- Five district labels and boundaries.
- Numbered locations and special-location colors.

Application overlays use muted ivory, ink black, evidence red, police blue,
and aged brass. Effects are limited to legibility and state: one active token
glow, one selection ring, one pending pulse, short page/drawer transitions,
and restrained paper depth. There are no decorative gradients, generic glass
cards, or unrelated dashboard chrome.

The existing IBM Plex family remains the complete UI type system:

- IBM Plex Serif for case titles, evidence prose, drawer headings, and the
  physical-book reading surface.
- IBM Plex Sans for controls, player names, location labels, and compact HUD
  copy.
- IBM Plex Mono for AP, Scratch, Day, version, coordinates, stamps, and
  connection telemetry.

No additional display font is introduced. This keeps long Vietnamese and
English text readable while retaining a restrained police-file character.

## Placement and Move Flow

### Selection

1. `GameBoard` receives legal IDs from the latest private projection.
2. Only those locations receive pointer and keyboard interaction.
3. Selecting a legal location updates a local, non-authoritative selection.
4. `ActionDock` shows a movement slip with origin, destination, shared
   district, and server-defined cost text.
5. Confirm sends `place` or `move`; Cancel clears the selection.

This two-step interaction prevents accidental moves on a dense board while
still making the primary gesture a map click. Selecting a different legal
hotspot replaces the pending destination without sending a command.

### Command

```json
{
  "command_id": "UUID",
  "type": "move",
  "expected_version": 18,
  "payload": {"location_id": "51"}
}
```

Placement uses the same envelope with `type: "place"`. The client does not
subtract AP, change location, or append history before the server accepts the
command.

### Authoritative result

The session serializes the command, validates membership, role, status, phase,
current turn, version, placement state, AP, destination existence, and shared
district. A successful transaction persists the event, snapshot, game version,
and player state before broadcasting.

The resulting public event includes the moving public player ID, origin,
destination, remaining AP, and new version. It contains no private evidence,
response type, solution, or Chisel notes.

After the authoritative projection arrives, the token moves to the new
coordinate over 300-450 ms. This is a visual transition between locations, not
a road-route simulation. Reduced-motion mode swaps immediately.

## Other Actions

The bottom dock is a projection renderer, not a fixed toolbar:

- Search Location opens the corresponding Search page in the casebook.
- Search Suspect first asks which colocated, server-projected suspect to search.
- Question opens only the server-projected suspect/topic combinations.
- Analyze confirms the one-action, one-Scratch exchange.
- Kickback appears only at a Mob Joint when unused on the current Day.
- Accuse appears only at the beginning of a turn with a Solve token and valid
  public accusation options.
- End Turn remains available according to `Rules.available_actions/2`.

Chisel response and leverage interactions use private user-topic data and the
same casebook drawer. They never enter the public projection merely to simplify
rendering.

## Failure and Reconnect Handling

- A command in flight disables only the relevant action, not the whole board.
- The dock shows a compact in-world pending label such as `Dispatching car`.
- `not_your_turn`, `invalid_destination`, `insufficient_ap`, `wrong_phase`,
  `game_paused`, and `stale_version` have distinct user-facing messages.
- An error clears the local selection unless the latest projection still makes
  the same destination legal.
- `stale_version` triggers projection resynchronization before interaction is
  restored.
- Duplicate `command_id` returns the stored result and cannot move twice or
  spend AP twice.
- A local channel error or close clears destination IDs, focusability, pending
  selection, online telemetry, and command controls immediately.
- Channel join alone does not restore interaction. A fresh public and private
  projection must arrive first.
- A persisted paused game shows the existing case-seal pause treatment; it does
  not preserve stale movement hotspots underneath.
- The server remains the final authority even when the client appears online.

## Accessibility and Responsive Behavior

- The board SVG has a descriptive label but does not hide interactive
  descendants behind a single `role="img"`.
- Only legal hotspots enter the tab order and behave as buttons.
- Enter and Space select the focused destination.
- A visible HTML list offers the same legal destinations, cost, and selection
  result without requiring precise pointer control.
- Focus rings remain visible over every district color and board texture.
- Touch targets are at least 44 by 44 CSS pixels even when the printed location
  box is smaller.
- Desktop supports contained pan and zoom without allowing the board to escape
  its interaction viewport.
- Mobile keeps at least 55vh for the map, uses a horizontally scrollable HUD,
  and renders the casebook as a bottom sheet.
- `prefers-reduced-motion` disables token travel, drawer flourish, pulses, and
  paper transitions without changing information.

## Test Strategy

### Catalog and validation tests

- Exactly 100 unique numbered locations load.
- Every number from 1 through 100 is present.
- Every location has valid coordinates and at least one known district.
- Police Station and Mob Joint classifications match the board reference.
- Every case location reference resolves to the catalog.
- Invalid overrides, duplicate numbers, and unknown location IDs are rejected.

### Rules and engine tests

- Classic Start accepts two, three, and four Detectives and rejects one or five.
- Default starting Days are 9, 8, and 7; a valid case override wins.
- First placement accepts any Police Station, costs zero AP, and cannot repeat.
- Move within a district costs one AP.
- A dual-district location bridges both districts.
- A destination with no shared district is rejected.
- Moving with zero AP, out of turn, in the wrong phase, or while paused is
  rejected.
- Free-Question state suppresses Move until resolved.
- Duplicate and stale commands leave location, AP, event sequence, and version
  consistent.

### Projection and security tests

- Only the active Detective receives legal placement or movement IDs.
- Chisel, inactive Detective, paused game, wrong phase, and zero-AP projections
  expose empty movement lists.
- Public movement events contain no solution, response type, hidden evidence,
  alternative responses, or Chisel notes.
- Users outside the game cannot join the game or user topics.
- Detective commands cannot invoke Chisel actions and vice versa.

### Svelte tests

- `GameBoard` emits selections only for legal IDs.
- Legal hotspots are keyboard reachable; illegal hotspots are not.
- Selection does not mutate the public token or AP.
- Confirm creates one command; Cancel creates none.
- New projections clear an invalid selection.
- Reduced-motion mode commits the authoritative token position without travel
  animation.

### Browser acceptance

Playwright uses independent Chisel and Detective browser contexts:

1. Start a strict Classic room with two Detectives and one Chisel.
2. Place the active Detective by clicking a Police Station and confirm that AP
   remains four.
3. Move within the current district and confirm AP becomes three only after the
   authoritative update.
4. Confirm a cross-district destination is not interactive while a border
   location is interactive.
5. Confirm the inactive Detective and Chisel cannot move the token.
6. Continue through Search or Question and End Turn from the server-driven dock.
7. Disconnect and reconnect the active Detective; stale hotspots stay disabled
   until fresh projections arrive.
8. Repeat the primary flow by keyboard and at 390x844 touch viewport.
9. Check 1440x900 desktop composition, board readability, drawer behavior, and
   zero console errors or warnings.

## Acceptance Criteria

- The exact official full-board image is the visible map background and is
  stored with source and non-commercial attribution metadata.
- The server owns a validated 100-location Classic board catalog.
- A production game starts only with one Chisel and two to four Detectives.
- Starting Day follows the 9/8/7 Classic defaults unless the case overrides it.
- Placement is free and limited to Police Stations.
- Movement costs one AP and uses shared district membership only.
- Only the active Detective sees and can operate legal map hotspots.
- No optimistic token or AP mutation occurs.
- The Chisel HUD does not display invented Detective resources.
- Search, Question, Analyze, Kickback, Accuse, and End Turn are rendered from
  `available_actions`.
- Reload, reconnect, stale version, duplicate command, and pause preserve
  authoritative state.
- Public and Detective payloads contain no Chisel secrets.
- Keyboard, reduced-motion, desktop, and mobile acceptance pass.
- `mix assets.build` is warning-free and `mix precommit` passes.
