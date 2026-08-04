# Cinema Noir Table System Design

## Status

Approved through visual-companion and text review on 2026-08-04.

The selected direction is a full-screen map rendered as a tactile 1940s noir
board-game table. The material palette is charred ebony, antique gold, sepia
paper, and signal red. The implementation approach is hybrid: CSS and SVG own
scalable structure and interaction states, while optimized local image assets
provide wood grain, paper fibers, portraits, tokens, stamps, and other tactile
detail.

This design extends, rather than replaces, the approved rules and authority
contract in `2026-08-04-cinematic-map-actions-design.md`.

## Goal

Make every application screen feel like part of one physical detective game,
not a collection of ordinary web cards. Dashboard, account, game creation,
invitation, lobby, and gameplay surfaces should look like objects arranged on
the same dark wood table while retaining semantic HTML, keyboard access,
Phoenix validation, and server-authoritative realtime state.

Gameplay remains map-first:

- The real *Detective: City of Angels* board image fills the viewport.
- Up to four Detective dossiers occupy a compact rail on the left.
- The Chisel console stays in the upper-right corner.
- Contextual paper cards appear only for the current selection or prompt.
- A physical action rail floats above the lower board edge.
- Tokens move only after the server persists and broadcasts the new state.

## Design Decisions

### Visual direction

- Cinema-noir presentation instead of a generic dashboard or open-book split.
- Charred ebony is the dominant framing material.
- Antique gold is reserved for fasteners, active edges, and important numbers.
- Sepia paper is the primary reading surface.
- Signal red marks destructive, urgent, selected, or sealed actions.
- The map stays dominant; furniture supports it instead of competing with it.

### Layout direction

- Full-screen, full-bleed map on desktop.
- Detective rail on the left with a maximum of four entries.
- Chisel console in the upper-right, visually distinct from Detective resources.
- Phase and current-turn plaque centered at the top.
- Context-card stack below the Chisel console.
- Action rail centered along the bottom edge.
- Casebook becomes an on-demand overlay, not a permanently open split view.

### Implementation direction

Use a hybrid visual system:

- CSS gradients, borders, masks, shadows, and SVG define scalable geometry.
- Local WebP or AVIF textures add restrained wood and paper variation.
- SVG provides brass corners, line ornaments, rings, route hints, and seals.
- Local portrait and token assets use licensed, generated, or original artwork.
- Semantic `button`, `nav`, `form`, heading, list, and dialog elements remain
  underneath every graphical control.

Raster-only chrome is rejected because it scales poorly and makes stateful
controls hard to maintain. CSS-only texture is rejected because repeated wood
and paper effects look synthetic at game-table scale.

## Scope

- Introduce a shared tactile visual system for all product screens.
- Reshape gameplay around the approved full-screen map composition.
- Replace fixed rectangular panels with object-like frames and contextual
  surfaces.
- Preserve the current LiveSvelte realtime flow and server authority.
- Preserve existing fonts and improve their hierarchy.
- Add subtle, state-driven transitions and reduced-motion alternatives.
- Define responsive layouts for desktop, tablet, and mobile landscape.
- Improve loading, stale-state, reconnect, paused, invalid-invite, and command
  error presentation using the same object language.
- Add visual and interaction coverage for the redesigned screens.

## Non-goals

- Rewriting game rules in JavaScript or Svelte.
- Optimistically changing AP, money, clues, location, phase, or winner.
- Replacing the official board image with an approximate generated map.
- Adding drag-and-drop movement or street-level pathfinding.
- Adding new commercial case content, secret casebooks, or copyrighted card
  scans.
- Adding React, Vue, DaisyUI, external script tags, or external stylesheet tags.
- Adding decorative animation that delays commands or hides server state.
- Changing authentication, game membership, or Channel authorization rules.

## Routes and Authentication

No new route is required.

Authenticated Dashboard, Create Game, Lobby, and Game LiveViews remain inside
the existing `live_session :require_authenticated_user` block and the browser
scope using `:require_authenticated_user`. These pages expose membership,
roles, private projections, or user-owned games and therefore require a logged
in `current_scope`.

Invite detail remains in the existing browser/current-user flow so an anonymous
visitor can inspect a valid invitation and then return after authentication.
Accepting the invitation still requires an authenticated scope.

Registration and login remain in the generated authentication scopes. The
visual redesign does not duplicate `live_session` names or introduce a
`current_user` assign. Templates continue reading `@current_scope.user` and
passing `current_scope` to `<Layouts.app>` and context calls.

## Visual Foundation

### Material tokens

The implementation defines a small set of CSS custom properties in
`assets/css/app.css` and uses Tailwind utilities for layout and responsive
behavior:

- `--noir-ebony-*`: table and frame surfaces.
- `--noir-gold-*`: brass lines, fasteners, active focus, and counters.
- `--noir-paper-*`: sepia sheets and readable dossier surfaces.
- `--noir-ink-*`: body text and printed rules.
- `--noir-red-*`: wax, selection, destructive commands, and urgent states.
- `--noir-shadow-*`: restrained elevation levels for paper, trays, and overlays.

Tailwind v4 keeps the generated Phoenix import structure. Raw CSS never uses
`@apply`. Runtime layouts reference only the supported `app.css` and `app.js`
bundles.

### Typography

The existing IBM Plex family remains the complete type system:

- IBM Plex Serif: case names, narrative copy, paper headings, and evidence.
- IBM Plex Sans: player names, controls, labels, and general UI copy.
- IBM Plex Mono: AP, Scratch, money, clues, Day, version, room code, and stamps.

No display font is added. IBM Plex supports Vietnamese, remains readable over
textured surfaces, and already fits the police-file tone.

### Texture rules

- Wood grain remains low-contrast and never passes through body text.
- Paper fibers remain below a contrast threshold that preserves long-form copy.
- One texture asset may tile, but scale and position vary by surface class to
  avoid an obvious repeated pattern.
- Brass is mostly flat with a narrow highlight; no glossy gold gradient.
- Shadows communicate physical stacking, not generic floating glass cards.
- Every texture has a solid-color fallback.

### Asset policy

The official local board image and its attribution metadata remain unchanged.
New interface assets must be original, generated for this project, or have a
license compatible with a public non-commercial repository. Source and license
metadata live adjacent to material assets when attribution is required.

All runtime graphics are local. There is no image hotlinking and no external
vendor script or stylesheet reference from layouts.

## Shared Graphical Primitives

The visual system uses a small set of reusable primitives instead of copying
complex texture markup into every page:

### `WoodFrame`

- Charred wood surround with inset shadow and optional brass corners.
- Supports `section`, `aside`, `nav`, and dialog semantics.
- Exposes compact, standard, and deep frame depths.
- Never owns domain state.

### `PaperSheet`

- Sepia reading surface with optional tape, clip, fold, or pin treatment.
- Supports headings, form fields, evidence prose, and contextual summaries.
- Texture is decorative and ignored by assistive technology.

### `BrassPlate`

- Compact label for phase, player resource, room code, or version.
- Uses IBM Plex Mono for numbers and terse status copy.
- Active state uses contrast and border change, not color alone.

### `WaxSeal`

- Represents Chisel authority, invite acceptance, revoked state, or sealed case.
- Interactive use remains a semantic button with visible focus.
- Decorative seal variants never receive click handlers.

### `GameToken`

- Represents a public board position or selected actor.
- Has deterministic coordinates and role-specific accessible labels.
- Motion runs only between authoritative public positions.

### `StatusStamp`

- Presents ready, paused, expired, invalid, full, retry, or resolved state.
- Includes readable text; it never relies on angled red lettering alone.

Primitive names describe visual responsibilities. Domain-specific state remains
in screen components and Phoenix contexts.

## Application Journey

### Account screens

Login, registration, and settings use a centered paper form on a restrained
wood desk. Inputs continue using the generated `<.input>` component and forms
continue using `to_form/2`. Password requirements and validation errors remain
plainly readable and are not hidden inside decorative seals.

### Dashboard

Dashboard becomes a case-file cabinet:

- Waiting, active, and finished games appear as labeled drawers or folders.
- Role, player count, current phase, and last activity remain scannable.
- The primary action opens a new case file.
- Empty states use one clean open drawer or blank folder, not a decorative card
  grid.
- Game collections continue using LiveView streams.

### Create Game

Create Game becomes a case-opening document laid on the desk:

- Room title, case version, capacity, and invite lifetime remain standard form
  controls with complete labels and validation.
- Published cases appear as dossier choices with a concise public synopsis.
- Secret case content never enters the selection payload.
- Submit appears as a seal-and-open action, while disabled and pending states
  remain explicit.

### Invitation

Invite detail becomes a summons letter:

- Room, case, Chisel, current seats, expiry, and remaining capacity are printed
  on the document.
- Accept is a wax-seal action.
- Expired, revoked, full, removed, and already-member states receive distinct
  stamps and explanatory copy.
- Login return-to behavior remains unchanged.

### Lobby

Lobby becomes a player tray:

- One Chisel position and up to four Detective seats are visible.
- Each occupied seat shows portrait, name, role, ready state, and online state.
- Empty capacity appears as an unoccupied physical slot.
- Invite copy, revoke, regenerate, remove player, ready, leave, and start actions
  remain permission-driven.
- Presence changes only the online indicator. Database membership owns the seat.
- Start remains disabled until the server reports every rule satisfied.

## Gameplay Composition

### `GameTableShell`

Owns viewport composition, responsive breakpoints, map dimming during blocking
overlays, and global focus order. It does not own Channels or game rules.

### `PlayerRail`

- Fixed along the left edge on desktop.
- Shows up to four Detective portraits, names, public resources, location,
  online state, and current-turn emphasis.
- Active Detective uses one controlled gold edge and token glow.
- Tablet mode compresses entries to portraits and essential counters.
- Selecting an entry opens public player detail without changing game state.

### `ChiselConsole`

- Fixed in the upper-right corner.
- Shows Chisel identity, public online state, and role-appropriate counters.
- Shows money, action, clue, or leverage only when those fields exist in the
  authoritative Chisel projection and rules contract.
- Never invents Detective AP or exposes Chisel secret fields through public
  props.
- Private prompts remain below it in the context stack.

### `MapStage`

- Wraps the existing `GameBoard` coordinate and hotspot behavior.
- Keeps the official map full-bleed and at its native aspect ratio.
- Owns pan/zoom bounds, public tokens, legal hotspots, selection ring, route
  preview, and completed-move transition.
- Receives locations and explicit legal IDs as props.
- Emits selection events only; it never sends Channel commands.

### `ContextStack`

- Appears below the Chisel console on desktop.
- Shows only the currently selected location, suspect, response prompt,
  evidence reveal, error, or required decision.
- Uses one primary sheet and at most two visible backing sheets.
- Replaces the always-open right-side casebook split.
- Tablet and mobile landscape use an anchored bottom drawer.

### `ActionRail`

- Fixed above the bottom edge without covering important map controls.
- Renders only actions present in `privateState.available_actions`.
- Selected action receives the signal-red physical key treatment.
- Disabled, pending, and unavailable are distinct states.
- Movement confirmation appears as a dispatch slip, not an immediate mutation.

### `CasebookOverlay`

- Opens on demand for Search, Question, Evidence, Accusation, history, Chisel
  casebook, and private notes.
- Uses a large paper dossier over a dimmed map.
- Keeps tabs role-specific and projection-driven.
- Restores prior focus when closed.
- On narrow screens it becomes a bottom sheet with map context still visible.

### `PauseCurtain`

- Blocks gameplay commands while paused or during mandatory reconnect sync.
- Shows the sealed case treatment and affected offline players.
- Does not leave stale hotspots focusable behind the overlay.

## Component and State Boundaries

`GameBook.svelte` remains the realtime coordinator:

```text
Phoenix Channels and projections
              |
              v
      GameBook coordinator
              |
       public/private props
              |
   +----------+-----------+
   |          |           |
PlayerRail  MapStage  ContextStack
ChiselHUD   ActionRail CasebookOverlay
   |          |           |
   +---- graphical primitives ----+
```

`GameBook.svelte` owns:

- Channel lifecycle and event de-duplication.
- Public/private projection reconciliation.
- Projection version synchronization.
- Command IDs, retry, timeout, and stale-state recovery.
- Local non-authoritative selection state.
- Mapping component events to Channel commands.

Presentation components own:

- Layout and accessible markup.
- Visual hover, focus, selected, pending, and resolved states.
- Local disclosure such as opening a public detail sheet.
- Motion between previous and next authoritative props.

Presentation components never own:

- AP, Scratch, money, clue, or leverage calculation.
- Command legality or phase transitions.
- Challenge results, evidence visibility, solution, or winner.
- Game membership, role, or Presence authority.

## Authoritative Movement Interaction

The approved map interaction uses four stages.

### 1. Select action

`ActionRail` enables Move only when both conditions hold:

- `available_actions` contains `move` or `place`.
- The corresponding legal-location projection contains at least one ID.

### 2. Select destination

- Only projected legal hotspots receive pointer and keyboard interaction.
- Clicking a legal hotspot creates local preview state.
- The map draws a restrained ring and optional straight route hint.
- `ContextStack` or a dispatch slip shows destination, server-defined cost text,
  and confirmation.
- The public token and resources remain unchanged.

### 3. Validate command

Confirmation sends the existing command envelope with `command_id`,
`expected_version`, and `location_id`. The GameSession validates actor, role,
status, phase, turn, AP, placement state, destination, and Classic district
rules before persistence.

### 4. Commit and animate

- Successful persistence updates event, snapshot, version, and player state.
- Public and private projections reconcile to the same version.
- The token transitions to the new authoritative coordinate.
- Reduced-motion mode updates it immediately.
- Invalid or stale commands leave the token at its previous coordinate.

No client code subtracts an action, moves a token, unlocks a location, or
advances a phase optimistically.

## Other Action Interactions

- Search opens a context sheet listing only searchable projected targets.
- Interrogate opens suspect and topic sheets, then sends the selected command.
- Chisel response selection appears only in the Chisel private context stack.
- Accept and Challenge become two deliberate stamped decisions on the latest
  published response.
- Analyze and Kickback include projected cost/reward copy but never compute it.
- Accusation opens a full dossier because it is high-impact and multi-field.
- End Turn remains a deliberate separate control with confirmation when unused
  actions remain.

Every action uses the same state vocabulary: unavailable, available, selected,
confirming, pending, committed, rejected, and resynchronizing.

## Errors, Loading, and Reconnect

### Command errors

- Validation error: context sheet receives a concise stamped reason.
- Stale version: controls lock, both projections refresh, then legal state is
  recomputed.
- Timeout: retry remains available with the original command ID.
- Duplicate command: stored result wins; no duplicate animation or cost.
- Invalidated selection: selected paper sheet closes and focus returns to the
  action or map landmark.

### Connection states

- Connecting: map is visible but interaction is covered by a thin loading
  plaque.
- Online but unsynchronized: all command controls remain disabled.
- Offline: case is stamped `Connection lost`; stale legal hotspots leave the
  tab order immediately.
- Paused: sealed-case overlay identifies missing players and resume authority.
- Reconnected: interaction returns only after matching public/private versions.

### Page and form errors

- Form errors stay adjacent to the relevant input.
- Global invitation or authorization failures use a paper notice and status
  stamp, never color alone.
- Empty states provide one useful next action and avoid filler copy.

## Motion

- Token travel: 300-450 ms transform between authoritative coordinates.
- Context sheet entrance: 160-220 ms opacity and small translate/rotate.
- Action key: 100-140 ms press depth.
- Drawer or dossier: 180-260 ms transform and opacity.
- Selection ring: restrained pulse only while a destination awaits confirmation.
- Error: one short 140-180 ms shake or stamp impact.
- Page-level transitions never delay navigation or Channel events.

`prefers-reduced-motion` disables travel interpolation, pulse, shake, paper
rotation, and decorative transitions while preserving state changes.

## Responsive Behavior

### Desktop

- Map fills viewport.
- Player rail stays left; Chisel and context stack stay right.
- Action rail stays bottom-center.
- Pan/zoom remains contained inside the board viewport.

### Tablet

- Player rail compresses to portrait slots.
- Chisel console reduces to identity and essential counters.
- Context stack becomes an anchored drawer.
- Action rail may scroll horizontally without shrinking touch targets.

### Mobile landscape

- Map remains the primary surface.
- Player and Chisel details open from compact edge trays.
- Action rail uses one-row horizontal scrolling.
- Casebook uses a bottom sheet and preserves visible map context.

### Mobile portrait

- A rotate-device notice is shown for active map interaction.
- Public state, history, casebook, reconnect status, and non-map decisions remain
  accessible.
- The notice is guidance, not a route or authentication blocker.

All interactive targets remain at least 44 by 44 CSS pixels. Visible focus is
maintained across wood, paper, and map backgrounds.

## Performance

- Texture assets are sized for their display role and encoded as WebP or AVIF.
- SVG ornaments are reused rather than duplicated as large inline documents.
- CSS grain remains static; no animated noise filter.
- Token motion uses transform and opacity only.
- Portraits and non-critical dossier art load lazily.
- The board image remains the largest visual asset and should not be duplicated
  in component bundles.
- Svelte components receive narrow props to avoid redrawing unrelated surfaces
  after every projection update.

## Test Strategy

### Domain and projection regression

- Keep all engine, movement, role, phase, idempotency, and projection tests.
- Add explicit payload assertions for each new Chisel and Detective component
  boundary.
- Confirm public and Detective props never contain solution, response type,
  hidden evidence, alternative responses, or Chisel notes.

### LiveView and component tests

- Use stable IDs for key navigation, forms, seats, HUD, map, action rail,
  context stack, overlays, and dialogs.
- Assert elements and outcomes with `has_element?/2` and `element/2`, not raw
  HTML text matching.
- Keep form tests driven through `to_form/2`, `<.input>`, `render_change/2`, and
  `render_submit/2`.
- Confirm authenticated routes remain in the existing required-auth session and
  public/current-user routes remain in their existing scope.

### Svelte interaction tests

- Visual primitives preserve semantic element type and focus behavior.
- Only legal map IDs can emit a selection.
- Preview state does not mutate token position or resources.
- Pending commands disable only relevant actions.
- New projections clear invalid selection and obsolete context.
- Role-specific components render only permitted fields.
- Reduced-motion mode skips decorative interpolation.

### Playwright acceptance

Use independent Chisel and Detective contexts to verify:

1. Account, Dashboard, Create Game, Invite, and Lobby share the approved visual
   system without console errors.
2. Lobby supports up to four Detective seats plus the separate Chisel seat.
3. Ready, Presence, invite, and start controls remain permission-correct.
4. The game opens with a full-screen map, left Detective rail, upper-right
   Chisel console, context stack, and bottom action rail.
5. Hover, keyboard focus, click preview, cancel, confirm, server commit, and
   token travel work for legal movement.
6. Illegal, out-of-turn, stale, timeout, reconnect, and paused flows never move
   the token optimistically.
7. Chisel and Detective private surfaces do not leak across browser contexts.
8. Desktop 1440x900, tablet, mobile landscape, and 390x844 portrait behavior
   match the responsive contract.
9. `prefers-reduced-motion` preserves all information and interaction.
10. No clipped controls, hidden focus, horizontal page overflow, warning, or
    error remains.

## Acceptance Criteria

- All scoped application screens share charred ebony, antique gold, sepia
  paper, and signal-red object language.
- The visual experience reads as a physical noir board game rather than a web
  dashboard.
- The official board image remains the exact full-screen gameplay map.
- Detective rail supports a maximum of four players; Chisel remains a separate
  upper-right console.
- Map context and action controls appear only when relevant.
- Buttons, forms, navigation, headings, lists, and dialogs remain semantic and
  keyboard accessible under the graphical treatment.
- Server projections remain the only source for visible actions, legal map
  areas, resources, role data, phase, result, and winner.
- Token position changes only after authoritative persistence and projection
  reconciliation.
- No public or Detective surface receives Chisel secret data.
- Reconnect, stale, timeout, paused, invalid invite, and form-error states have
  clear in-world presentation.
- Desktop, tablet, mobile landscape, portrait guidance, keyboard, and reduced
  motion acceptance pass.
- Runtime uses only local assets through `app.js` and `app.css`.
- Tailwind v4 import syntax remains intact and raw CSS contains no `@apply`.
- `npm run test:ui`, `mix assets.build`, and `mix precommit` pass without
  warnings.
