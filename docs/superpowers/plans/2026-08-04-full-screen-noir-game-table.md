# Full-Screen Noir Game Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the open-book gameplay split with a full-screen authoritative map, left Detective rail, upper-right Chisel console, contextual paper stack, bottom action rail, and on-demand casebook overlay.

**Architecture:** Keep `GameBook.svelte` as Channel and projection coordinator. Extract presentation into focused Svelte components that receive allow-listed props and emit intent callbacks; only `GameBook` sends commands. Add a local action-mode and destination preview, but commit token position and resources only from reconciled server projections.

**Tech Stack:** Phoenix Channels, LiveSvelte, Svelte 5 runes, Tailwind CSS 4, SVG map overlays, Vitest, Testing Library, Playwright, ExUnit.

## Global Constraints

- Complete `2026-08-04-cinema-noir-app-journey.md` first; this plan consumes its material primitives and CSS tokens.
- Keep the exact local board asset at `/images/maps/dcoa/game-board-final.png` and retain visible attribution.
- Keep `GameBook.svelte` as the only browser module that joins game and user Channels or pushes commands.
- Never change AP, Scratch, money, clues, leverage, location, phase, result, or winner optimistically.
- Render actions only from `privateState.available_actions`.
- Make map hotspots interactive only from projected placement or movement IDs and the selected local action mode.
- Keep public and private projection versions synchronized before enabling controls.
- Keep Chisel secrets inside Chisel private props; never pass raw Chisel private state into Detective-only components.
- Keep the game route in the existing authenticated `live_session :require_authenticated_user` because membership and private projections require login.
- Use local graphics through `app.js` and `app.css`; no DaisyUI, `@apply`, external scripts, or external stylesheets.
- Preserve keyboard interaction, 44px targets, visible focus, and `prefers-reduced-motion` behavior.
- Prefix every shell command with `rtk`.

---

## File Map

### Table composition

- Create `assets/svelte/game/GameTableShell.svelte`: viewport composition and phase plaque.
- Create `assets/svelte/game/GameTableShell.test.js`: landmarks and status contract.
- Create `assets/svelte/game/DetectiveRail.svelte`: four fixed Detective dossier slots.
- Create `assets/svelte/game/ChiselConsole.svelte`: separate Chisel identity and private prompt surface.
- Create `assets/svelte/game/GameHud.test.js`: role separation and leakage coverage.
- Delete `assets/svelte/game/PlayerHUD.svelte` after integration.
- Delete `assets/svelte/game/PlayerHUD.test.js` after replacement tests pass.

### Map and command surfaces

- Create `assets/svelte/game/MapStage.svelte`: full-screen map frame, status plaque, and attribution.
- Create `assets/svelte/game/MapStage.test.js`: legal-mode and selection coverage.
- Modify `assets/svelte/game/GameBoard.svelte`: remove document-style frame and fallback-list placement from the visual surface.
- Modify `assets/svelte/game/GameBoard.test.js`: preserve hotspot, keyboard, official image, and token tests.
- Create `assets/svelte/game/ContextStack.svelte`: destination slip, pending, stale, and error sheets.
- Create `assets/svelte/game/ContextStack.test.js`: preview/confirm/cancel/error behavior.
- Create `assets/svelte/game/ActionRail.svelte`: projected physical action keys and local Move mode.
- Create `assets/svelte/game/ActionRail.test.js`: exact action projection and intent coverage.
- Delete `assets/svelte/game/ActionDock.svelte` after integration.
- Delete `assets/svelte/game/ActionDock.test.js` after replacement tests pass.

### Dossiers and blocking state

- Create `assets/svelte/game/CasebookOverlay.svelte`: modal dossier shell with focus return.
- Create `assets/svelte/game/CasebookOverlay.test.js`: Escape, close, labeling, and focus return.
- Create `assets/svelte/game/CasebookWorkspace.svelte`: role-aware dossier page presentation.
- Create `assets/svelte/game/CasebookWorkspace.test.js`: page routing and Chisel-secret boundary.
- Delete `assets/svelte/game/CasebookDrawer.svelte` after integration.
- Delete `assets/svelte/game/CasebookDrawer.test.js` after replacement tests pass.
- Create `assets/svelte/game/PauseCurtain.svelte`: paused/reconnect blocking document.
- Create `assets/svelte/game/PauseCurtain.test.js`: inert and resume-authority contract.

### Orchestration and verification

- Modify `assets/svelte/GameBook.svelte`: compose extracted components and add local action mode.
- Modify `assets/css/app.css`: full-screen table layout, object surfaces, motion, responsive behavior, and reduced motion.
- Modify `test/detective_web/live/game_live_test.exs`: projection allow-list regression.
- Keep existing Channel, engine, projection, and rules tests unchanged unless a selector-only assertion requires updating.

---

### Task 1: Build the full-screen table shell

**Files:**
- Create: `assets/svelte/game/GameTableShell.svelte`
- Create: `assets/svelte/game/GameTableShell.test.js`
- Modify: `assets/css/app.css`

**Interfaces:**
- Consumes: `phase`, `day`, `daysRemaining`, `activeDetectiveName`, `connectionState`, `version`, and six optional snippets: `detectiveRail`, `chiselConsole`, `mapStage`, `contextStack`, `actionRail`, `overlay`.
- Produces: stable regions `#game-table-shell`, `#game-phase-plaque`, `#game-detective-rail-region`, `#game-chisel-region`, `#game-map-region`, `#game-context-region`, `#game-action-region`, and `#game-overlay-region`.

- [ ] **Step 1: Write the failing shell test**

```javascript
import { createRawSnippet } from "svelte"
import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import GameTableShell from "./GameTableShell.svelte"

const snippet = (text) => createRawSnippet(() => ({ render: () => `<span>${text}</span>` }))

describe("GameTableShell", () => {
  it("keeps the map primary and exposes every table landmark", () => {
    render(GameTableShell, {
      phase: "detective_turn",
      day: 8,
      daysRemaining: 6,
      activeDetectiveName: "Marlowe",
      connectionState: "online",
      version: 19,
      detectiveRail: snippet("players"),
      chiselConsole: snippet("chisel"),
      mapStage: snippet("map"),
      contextStack: snippet("context"),
      actionRail: snippet("actions"),
      overlay: snippet("overlay"),
    })

    expect(document.querySelector("#game-table-shell.noir-game-table")).toBeInTheDocument()
    expect(screen.getByRole("main")).toContainElement(document.querySelector("#game-map-region"))
    expect(document.querySelector("#game-detective-rail-region")).toHaveTextContent("players")
    expect(document.querySelector("#game-chisel-region")).toHaveTextContent("chisel")
    expect(document.querySelector("#game-action-region")).toHaveTextContent("actions")
    expect(document.querySelector("#game-phase-plaque")).toHaveTextContent("Marlowe")
  })
})
```

- [ ] **Step 2: Run the test and verify missing module failure**

Run: `rtk npm run test:ui -- assets/svelte/game/GameTableShell.test.js`

Expected: FAIL because `GameTableShell.svelte` does not exist.

- [ ] **Step 3: Implement the shell with semantic regions**

```svelte
<script>
  let {
    phase,
    day,
    daysRemaining,
    activeDetectiveName,
    connectionState,
    version,
    detectiveRail,
    chiselConsole,
    mapStage,
    contextStack,
    actionRail,
    overlay,
  } = $props()
</script>

<main id="game-table-shell" class="noir-game-table">
  <section id="game-map-region" class="noir-game-map-region" aria-label="Investigation map">
    {@render mapStage?.()}
  </section>

  <header id="game-phase-plaque" class="noir-game-phase" aria-live="polite">
    <span>Day {day} · {daysRemaining} remaining</span>
    <strong>{phase.replaceAll("_", " ")} · {activeDetectiveName ?? "No active Detective"}</strong>
    <span>{connectionState} · v{version}</span>
  </header>

  <aside id="game-detective-rail-region" class="noir-game-detective-rail" aria-label="Detectives">
    {@render detectiveRail?.()}
  </aside>
  <aside id="game-chisel-region" class="noir-game-chisel" aria-label="Chisel">
    {@render chiselConsole?.()}
  </aside>
  <aside id="game-context-region" class="noir-game-context" aria-label="Current context">
    {@render contextStack?.()}
  </aside>
  <nav id="game-action-region" class="noir-game-actions" aria-label="Game actions">
    {@render actionRail?.()}
  </nav>
  <aside class="noir-map-rotate-notice" aria-live="polite">
    Rotate to landscape to interact with the map. Casebook and game status remain available.
  </aside>
  <div id="game-overlay-region">{@render overlay?.()}</div>
</main>
```

- [ ] **Step 4: Add the fixed desktop composition**

```css
.noir-game-table {
  position: relative;
  min-height: calc(100dvh - 3.5rem);
  overflow: hidden;
  background: var(--noir-ebony-950);
  color: #f0dfbd;
}

.noir-game-map-region { position: absolute; inset: 0; }
.noir-game-phase { position: absolute; z-index: 30; left: 50%; top: 1rem; translate: -50% 0; }
.noir-game-detective-rail { position: absolute; z-index: 30; left: 1rem; top: 50%; translate: 0 -50%; }
.noir-game-chisel { position: absolute; z-index: 30; right: 1rem; top: 1rem; }
.noir-game-context { position: absolute; z-index: 29; right: 1rem; top: 11.75rem; }
.noir-game-actions { position: absolute; z-index: 30; bottom: 1rem; left: 50%; translate: -50% 0; }
```

- [ ] **Step 5: Run shell test and build**

Run: `rtk npm run test:ui -- assets/svelte/game/GameTableShell.test.js`

Expected: PASS.

Run: `rtk mix assets.build`

Expected: client and SSR builds pass without warning.

- [ ] **Step 6: Commit**

```bash
rtk git add assets/svelte/game/GameTableShell.svelte assets/svelte/game/GameTableShell.test.js assets/css/app.css
rtk git commit -m "feat(game): add full-screen table shell"
```

### Task 2: Split Detective rail and Chisel console

**Files:**
- Create: `assets/svelte/game/DetectiveRail.svelte`
- Create: `assets/svelte/game/ChiselConsole.svelte`
- Create: `assets/svelte/game/GameHud.test.js`
- Modify: `assets/css/app.css`

**Interfaces:**
- `DetectiveRail` consumes `players`, `currentDetectiveId`, `ownPlayerId`, `privateResources`, `onlinePlayerIds`, `connectionSnapshotReceived`, and `disconnectLabel`.
- `privateResources` contains only `%{scratch, leverage}` for the current Detective or is `null`.
- `ChiselConsole` consumes `chisel`, `isCurrentChisel`, `pendingInterrogation`, `leverageByDetective`, `detectiveSlots`, `online`, and `connectionLabel`.
- Detective rail never receives `leverageByDetective`, `pendingInterrogation`, solution, response options, or Chisel notes.

- [ ] **Step 1: Write failing role-boundary tests**

```javascript
import { render, screen, within } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import ChiselConsole from "./ChiselConsole.svelte"
import DetectiveRail from "./DetectiveRail.svelte"

const players = [
  { id: "d1", role: "detective", seat: 1, display_name: "Marlowe", actions_remaining: 3, location_id: "51" },
  { id: "d3", role: "detective", seat: 3, display_name: "Vega", actions_remaining: 2, location_id: "84" },
]

describe("game HUD role boundaries", () => {
  it("renders four fixed Detective slots and only the current Detective private resources", () => {
    render(DetectiveRail, {
      players,
      currentDetectiveId: "d1",
      ownPlayerId: "d1",
      privateResources: { scratch: 6, leverage: 3 },
      onlinePlayerIds: ["d1"],
      connectionSnapshotReceived: true,
      disconnectLabel: () => "OFFLINE",
    })

    expect(screen.getAllByTestId(/detective-rail-slot-/)).toHaveLength(4)
    expect(screen.getByTestId("detective-rail-slot-1")).toHaveTextContent("Scratch 6")
    expect(screen.getByTestId("detective-rail-slot-3")).not.toHaveTextContent("Scratch")
  })

  it("keeps Chisel-private leverage inside the Chisel console", () => {
    render(ChiselConsole, {
      chisel: { id: "c1", display_name: "The Chisel" },
      isCurrentChisel: true,
      pendingInterrogation: { id: "pending" },
      leverageByDetective: { d1: 2, d3: 1 },
      detectiveSlots: players,
      online: true,
      connectionLabel: "ONLINE",
    })

    const consoleElement = screen.getByTestId("chisel-console")
    expect(consoleElement).toHaveTextContent("Response open")
    expect(consoleElement).toHaveTextContent("D1 2")
    expect(within(consoleElement).queryByText(/AP/)).not.toBeInTheDocument()
    expect(within(consoleElement).queryByText(/Scratch/)).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the tests and verify missing module failure**

Run: `rtk npm run test:ui -- assets/svelte/game/GameHud.test.js`

Expected: FAIL because both components are missing.

- [ ] **Step 3: Extract Detective display logic**

Move the existing four-seat derivation, connection labels, portrait display,
active-turn state, own Scratch, and own leverage total into `DetectiveRail`.
Use `PortraitToken` from the app-journey plan. Render fixed IDs
`detective-rail-slot-1` through `detective-rail-slot-4`. Use a vertical wood
tray on desktop and a horizontal compact tray below 64rem.

Calculate `privateResources` in `GameBook`, not in `DetectiveRail`:

```javascript
let ownPrivateResources = $derived.by(() => {
  if (privateState.role !== "detective") return null
  const committed = Object.values(privateState.leverage_on_suspects ?? {}).reduce(
    (sum, value) => sum + value,
    0,
  )
  return {
    scratch: privateState.scratch ?? 0,
    leverage: (privateState.leverage_supply ?? 0) + committed,
  }
})
```

- [ ] **Step 4: Extract Chisel-private display logic**

Move Chisel identity, Presence label, pending-response state, and
`leverage_by_detective` display into `ChiselConsole`. When `isCurrentChisel` is
false, render `Private controls sealed` and do not render private rows. Do not
add AP, Scratch, money, or clue counters unless a future authoritative Chisel
projection explicitly defines them.

- [ ] **Step 5: Run HUD tests**

Run: `rtk npm run test:ui -- assets/svelte/game/GameHud.test.js`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add assets/svelte/game/DetectiveRail.svelte assets/svelte/game/ChiselConsole.svelte assets/svelte/game/GameHud.test.js assets/css/app.css
rtk git commit -m "refactor(game): split role HUD surfaces"
```

### Task 3: Wrap the official board in a full-screen MapStage

**Files:**
- Create: `assets/svelte/game/MapStage.svelte`
- Create: `assets/svelte/game/MapStage.test.js`
- Modify: `assets/svelte/game/GameBoard.svelte`
- Modify: `assets/svelte/game/GameBoard.test.js`
- Modify: `assets/css/app.css`

**Interfaces:**
- `MapStage` consumes `locations`, `detectives`, `legalLocationIds`, `selectedLocationId`, `pendingLocationId`, `lastTravel`, `disabled`, `status`, and `onSelect`.
- `GameBoard` keeps the same prop contract.
- `MapStage` passes an empty legal ID array when `disabled` is true.
- `MapStage` owns presentation-only zoom levels `1`, `1.25`, `1.5`, `1.75`, `2`, `2.25`, and `2.5`; its contained overflow region provides pan without changing map coordinates.

- [ ] **Step 1: Write failing MapStage tests**

```javascript
import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"
import MapStage from "./MapStage.svelte"

const location = {
  id: "51",
  name: "L.A. Police Department Headquarters",
  type: "police_station",
  district_ids: ["central_la"],
  x: 0.52,
  y: 0.5,
}

describe("MapStage", () => {
  it("forwards only enabled legal destination intent", async () => {
    const onSelect = vi.fn()
    const { rerender } = render(MapStage, {
      locations: [location],
      detectives: [],
      legalLocationIds: ["51"],
      selectedLocationId: null,
      pendingLocationId: null,
      lastTravel: null,
      disabled: true,
      status: "Choose Move",
      onSelect,
    })

    await fireEvent.click(screen.getByTestId("map-hotspot-51"))
    expect(onSelect).not.toHaveBeenCalled()

    await rerender({
      locations: [location],
      detectives: [],
      legalLocationIds: ["51"],
      selectedLocationId: null,
      pendingLocationId: null,
      lastTravel: null,
      disabled: false,
      status: "Choose destination",
      onSelect,
    })
    await fireEvent.click(screen.getByTestId("map-hotspot-51"))
    expect(onSelect).toHaveBeenCalledWith(location)
  })

  it("keeps board attribution visible", () => {
    render(MapStage, {
      locations: [location],
      detectives: [],
      legalLocationIds: [],
      selectedLocationId: null,
      pendingLocationId: null,
      lastTravel: null,
      disabled: false,
      status: "Observing",
      onSelect: vi.fn(),
    })
    expect(screen.getByText(/Van Ryder Games/)).toBeInTheDocument()
  })

  it("zooms inside the contained map viewport", async () => {
    render(MapStage, {
      locations: [location],
      detectives: [],
      legalLocationIds: [],
      selectedLocationId: null,
      pendingLocationId: null,
      lastTravel: null,
      disabled: false,
      status: "Observing",
      onSelect: vi.fn(),
    })
    await fireEvent.click(screen.getByRole("button", { name: "Zoom in" }))
    expect(document.querySelector("#map-zoom-plane")).toHaveAttribute("data-zoom", "1.25")
    await fireEvent.click(screen.getByRole("button", { name: "Reset map zoom" }))
    expect(document.querySelector("#map-zoom-plane")).toHaveAttribute("data-zoom", "1")
  })
})
```

- [ ] **Step 2: Run tests and verify missing component failure**

Run: `rtk npm run test:ui -- assets/svelte/game/MapStage.test.js`

Expected: FAIL because `MapStage.svelte` does not exist.

- [ ] **Step 3: Implement MapStage**

```svelte
<script>
  import GameBoard from "./GameBoard.svelte"
  let {
    locations = [], detectives = [], legalLocationIds = [], selectedLocationId = null,
    pendingLocationId = null, lastTravel = null, disabled = false, status = "",
    onSelect = () => {},
  } = $props()
  const zoomLevels = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.5]
  let zoomIndex = $state(0)
  let zoom = $derived(zoomLevels[zoomIndex])
</script>

<section id="map-stage" class="noir-map-stage" aria-labelledby="game-map-title">
  <div id="map-stage-status" class="noir-map-status" aria-live="polite" aria-busy={pendingLocationId !== null}>
    {status}
  </div>
  <div class="noir-map-zoom-controls" aria-label="Map zoom controls">
    <button type="button" aria-label="Zoom out" disabled={zoomIndex === 0} onclick={() => (zoomIndex -= 1)}>−</button>
    <button type="button" aria-label="Reset map zoom" onclick={() => (zoomIndex = 0)}>1:1</button>
    <button type="button" aria-label="Zoom in" disabled={zoomIndex === zoomLevels.length - 1} onclick={() => (zoomIndex += 1)}>+</button>
  </div>
  <div class="noir-map-pan-region">
    <div id="map-zoom-plane" data-zoom={zoom} style={`width: ${zoom * 100}%;`}>
      <GameBoard
        {locations}
        {detectives}
        legalLocationIds={disabled ? [] : legalLocationIds}
        {selectedLocationId}
        {pendingLocationId}
        {lastTravel}
        {disabled}
        {onSelect}
      />
    </div>
  </div>
  <p id="board-attribution" class="noir-board-attribution">
    Board artwork © Van Ryder Games / Vincent Dutrait. Unofficial non-commercial fan project; not affiliated with or endorsed by the publisher.
  </p>
</section>
```

- [ ] **Step 4: Make GameBoard fill its stage**

Remove the outer document border and restyle the existing fallback destination
list as an absolutely positioned, visually compact disclosure at the
lower-left of `GameBoard`. Keep it present and keyboard equivalent. Add a
vignette through a `MapStage` pseudo-element outside the SVG. Preserve the
`viewBox`, official image, legal hotspot roles, target circles, token IDs,
travel trace, and reduced-motion rules.

Use contained overflow for zoom and pan:

```css
.noir-map-pan-region { width: 100%; height: 100%; overflow: auto; overscroll-behavior: contain; }
#map-zoom-plane { min-width: 100%; transform-origin: 0 0; }
.noir-map-zoom-controls { position: absolute; z-index: 8; right: 1rem; bottom: 1rem; display: flex; }
.noir-map-zoom-controls button { min-width: 2.75rem; min-height: 2.75rem; }
```

- [ ] **Step 5: Run all map tests**

Run: `rtk npm run test:ui -- assets/svelte/game/GameBoard.test.js assets/svelte/game/MapStage.test.js`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add assets/svelte/game/GameBoard.svelte assets/svelte/game/GameBoard.test.js assets/svelte/game/MapStage.svelte assets/svelte/game/MapStage.test.js assets/css/app.css
rtk git commit -m "feat(game): stage official map full-screen"
```

### Task 4: Add action mode, ContextStack, and ActionRail

**Files:**
- Create: `assets/svelte/game/ContextStack.svelte`
- Create: `assets/svelte/game/ContextStack.test.js`
- Create: `assets/svelte/game/ActionRail.svelte`
- Create: `assets/svelte/game/ActionRail.test.js`
- Modify: `assets/css/app.css`

**Interfaces:**
- `ActionRail` consumes `availableActions`, `activeAction`, `commandPending`, `connectionOnline`, `onChooseAction`, `onAction`, and `onOpenCasebook`.
- `ActionRail` emits `onChooseAction("place")` or `onChooseAction("move")`; every other exact projected action goes to `onAction(id)`.
- `ContextStack` consumes `selection`, `origin`, `commandPending`, `commandError`, `commandStatus`, `connectionOnline`, `onConfirmMove`, and `onCancelMove`.
- Neither component receives `gameChannel` or mutates public/private projections.

- [ ] **Step 1: Write failing ActionRail tests**

```javascript
import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"
import ActionRail from "./ActionRail.svelte"

describe("ActionRail", () => {
  it("renders projected game actions plus the casebook utility", async () => {
    const onChooseAction = vi.fn()
    const onAction = vi.fn()
    const onOpenCasebook = vi.fn()
    render(ActionRail, {
      availableActions: ["move", "analyze", "end_turn"],
      activeAction: null,
      commandPending: false,
      connectionOnline: true,
      onChooseAction,
      onAction,
      onOpenCasebook,
    })

    await fireEvent.click(screen.getByRole("button", { name: "Move" }))
    await fireEvent.click(screen.getByRole("button", { name: "Analyze" }))
    await fireEvent.click(screen.getByRole("button", { name: "Casebook" }))
    expect(onChooseAction).toHaveBeenCalledWith("move")
    expect(onAction).toHaveBeenCalledWith("analyze")
    expect(onOpenCasebook).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole("button", { name: "Kickback" })).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Write failing ContextStack tests**

```javascript
import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"
import ContextStack from "./ContextStack.svelte"

const selection = {
  type: "move",
  location: { id: "48", name: "Bradbury Building", district_ids: ["central_la"] },
}

describe("ContextStack", () => {
  it("previews without confirming until the physical control is clicked", async () => {
    const onConfirmMove = vi.fn()
    render(ContextStack, {
      selection,
      origin: { id: "51", name: "LAPD Headquarters" },
      commandPending: false,
      commandError: null,
      commandStatus: false,
      connectionOnline: true,
      onConfirmMove,
      onCancelMove: vi.fn(),
    })

    expect(onConfirmMove).not.toHaveBeenCalled()
    expect(screen.getByText("Bradbury Building")).toBeInTheDocument()
    await fireEvent.click(screen.getByRole("button", { name: "Confirm Move" }))
    expect(onConfirmMove).toHaveBeenCalledWith(selection)
  })

  it("announces stale sync as status rather than an alert", () => {
    render(ContextStack, {
      selection: null,
      origin: null,
      commandPending: false,
      commandError: "Game state changed; map resynchronized",
      commandStatus: true,
      connectionOnline: true,
      onConfirmMove: vi.fn(),
      onCancelMove: vi.fn(),
    })
    expect(screen.getByRole("status")).toHaveTextContent("map resynchronized")
    expect(screen.queryByRole("alert")).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 3: Run tests and verify missing component failures**

Run: `rtk npm run test:ui -- assets/svelte/game/ActionRail.test.js assets/svelte/game/ContextStack.test.js`

Expected: FAIL because both components are missing.

- [ ] **Step 4: Implement exact projected action definitions**

Use this definition list in `ActionRail`:

```javascript
const actionDefinitions = [
  { id: "place", label: "Place", mode: true },
  { id: "move", label: "Move", mode: true },
  { id: "search_location", label: "Search Location" },
  { id: "search_suspect", label: "Search Suspect" },
  { id: "interrogate", label: "Question Suspect" },
  { id: "analyze", label: "Analyze" },
  { id: "kickback", label: "Kickback" },
  { id: "skip_free_question", label: "Decline Free Question" },
  { id: "accuse", label: "Accuse", danger: true },
  { id: "submit_final_guess", label: "Seal Final Guess", danger: true },
  { id: "end_turn", label: "End Turn", danger: true },
]
```

Filter with `new Set(availableActions)`. Mode buttons call `onChooseAction`;
other projected buttons call `onAction`. Render one separate Casebook utility
button that calls `onOpenCasebook` and never sends a game command. Mark active
mode with `aria-pressed`. Disable all command buttons while offline or pending;
the Casebook utility remains available for reading during a connection loss.

- [ ] **Step 5: Implement contextual destination paper**

Move the existing movement-slip content from `ActionDock` into `ContextStack`.
Keep origin, destination, district list, free Placement wording, pending label,
confirm, cancel, alert/status distinction, and disabled behavior. Render no
empty card when there is no selection and no command message.

- [ ] **Step 6: Run action and context tests**

Run: `rtk npm run test:ui -- assets/svelte/game/ActionRail.test.js assets/svelte/game/ContextStack.test.js`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
rtk git add assets/svelte/game/ActionRail.svelte assets/svelte/game/ActionRail.test.js assets/svelte/game/ContextStack.svelte assets/svelte/game/ContextStack.test.js assets/css/app.css
rtk git commit -m "feat(game): add contextual action controls"
```

### Task 5: Replace the drawer with an accessible casebook overlay

**Files:**
- Create: `assets/svelte/game/CasebookOverlay.svelte`
- Create: `assets/svelte/game/CasebookOverlay.test.js`
- Modify: `assets/css/app.css`

**Interfaces:**
- Consumes: `open`, `title`, `page`, `pages`, `onSelectPage`, `onClose`, and `children` snippet.
- Produces: `#casebook-overlay`, `#casebook-dialog`, `#close-casebook-overlay`, and `#casebook-overlay-content`.
- Restores focus to the element active when the overlay opened.

- [ ] **Step 1: Write failing overlay tests**

```javascript
import { createRawSnippet } from "svelte"
import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"
import CasebookOverlay from "./CasebookOverlay.svelte"

const content = createRawSnippet(() => ({ render: () => "<p>Private evidence</p>" }))

describe("CasebookOverlay", () => {
  it("labels the dialog and closes with Escape", async () => {
    const onClose = vi.fn()
    render(CasebookOverlay, {
      open: true,
      title: "Evidence",
      page: "evidence",
      pages: [{ id: "evidence", label: "Evidence" }],
      onSelectPage: vi.fn(),
      onClose,
      children: content,
    })

    expect(screen.getByRole("dialog", { name: "Evidence" })).toBeInTheDocument()
    expect(screen.getByText("Private evidence")).toBeInTheDocument()
    await fireEvent.keyDown(window, { key: "Escape" })
    expect(onClose).toHaveBeenCalledTimes(1)
  })
})
```

- [ ] **Step 2: Run the test and verify missing module failure**

Run: `rtk npm run test:ui -- assets/svelte/game/CasebookOverlay.test.js`

Expected: FAIL because `CasebookOverlay.svelte` does not exist.

- [ ] **Step 3: Implement modal semantics and focus return**

Use the existing focus-capture and Escape logic from `CasebookDrawer`, but
render:

```svelte
{#if open}
  <div id="casebook-overlay" class="noir-casebook-backdrop">
    <section
      id="casebook-dialog"
      class="noir-casebook-dialog noir-paper-sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="casebook-overlay-title"
    >
      <header class="noir-casebook-header">
        <div>
          <p>Detective field folio</p>
          <h2 id="casebook-overlay-title">{title}</h2>
        </div>
        <button id="close-casebook-overlay" type="button" aria-label="Close casebook" onclick={requestClose}>×</button>
      </header>
      <nav aria-label="Casebook pages">
        {#each pages as entry}
          <button type="button" aria-pressed={page === entry.id} onclick={() => onSelectPage(entry.id)}>
            {entry.label}
          </button>
        {/each}
      </nav>
      <div id="casebook-overlay-content">{@render children?.()}</div>
    </section>
  </div>
{/if}
```

Add desktop dossier sizing, tablet bottom-sheet behavior, visible focus, map
dimming, scroll containment, and reduced-motion CSS.

- [ ] **Step 4: Run overlay tests**

Run: `rtk npm run test:ui -- assets/svelte/game/CasebookOverlay.test.js`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add assets/svelte/game/CasebookOverlay.svelte assets/svelte/game/CasebookOverlay.test.js assets/css/app.css
rtk git commit -m "feat(game): add casebook overlay"
```

### Task 6: Extract role-aware casebook page presentation

**Files:**
- Create: `assets/svelte/game/CasebookWorkspace.svelte`
- Create: `assets/svelte/game/CasebookWorkspace.test.js`
- Modify: `assets/svelte/GameBook.svelte`

**Interfaces:**
- Consumes: `page`, `view`, and `actions`.
- `view` contains only these allow-listed keys: `role`, `phase`, `result`, `activeDetective`, `ownPlayer`, `availableActions`, `search`, `question`, `evidence`, `accusation`, `history`, and `chisel`.
- `view.search` contains `suspects`, `selectedSuspectId`, `searchableSuspectIds`, and `interrogatableSuspectIds`.
- `view.question` contains `pendingPublic`, role-appropriate `pendingPrivate`, `latestStatement`, `interrogationOptions`, `selectedSuspectId`, `selectedTopicId`, `selectedSuspectLeverage`, `spendLeverage`, `selectedResponseId`, and `blockedSnitchPlayerIds`.
- `view.evidence` contains `heldEvidence`, `knownCaseCards`, and `latestSearch`.
- `view.accusation` contains `options`, `selectedSuspectId`, `selectedWeaponId`, `selectedMotiveId`, `solveAttempt`, and `finalGuess`.
- `view.history` contains `entries` already mapped to `%{type, actorName}`, `lastEvent`, `commandError`, `commandStatus`, and `retryAvailable`.
- `view.chisel` is `null` unless `role === "chisel"`; it is the only key allowed to contain solution, response type, response options, or Chisel notes.
- `actions` contains `selectSuspect`, `selectTopic`, `setSpendLeverage`, `submitSuspectSearch`, `submitInterrogation`, `allowQuestion`, `blockQuestion`, `acceptQuestionBlock`, `bribeGoon`, `declineSnitch`, `chooseSnitch`, `setBlockedSnitchPlayers`, `submitSnitchResolution`, `selectResponse`, `submitResponse`, `acceptResponse`, `challengeResponse`, `setAccusationSuspect`, `setAccusationWeapon`, `setAccusationMotive`, `submitAccusation`, and `retryCommand` callbacks.

- [ ] **Step 1: Write failing workspace boundary tests**

```javascript
import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import CasebookWorkspace from "./CasebookWorkspace.svelte"

const noActions = {
  selectSuspect: () => {},
  selectTopic: () => {},
  setSpendLeverage: () => {},
  submitSuspectSearch: () => {},
  submitInterrogation: () => {},
  allowQuestion: () => {},
  blockQuestion: () => {},
  acceptQuestionBlock: () => {},
  bribeGoon: () => {},
  declineSnitch: () => {},
  chooseSnitch: () => {},
  setBlockedSnitchPlayers: () => {},
  submitSnitchResolution: () => {},
  selectResponse: () => {},
  submitResponse: () => {},
  acceptResponse: () => {},
  challengeResponse: () => {},
  setAccusationSuspect: () => {},
  setAccusationWeapon: () => {},
  setAccusationMotive: () => {},
  submitAccusation: () => {},
  retryCommand: () => {},
}

const baseView = {
  role: "detective",
  phase: "detective_turn",
  result: null,
  activeDetective: { id: "d1", display_name: "Marlowe" },
  ownPlayer: { id: "d1", actions_remaining: 3 },
  availableActions: ["interrogate"],
  search: { suspects: [], selectedSuspectId: null, searchableSuspectIds: [], interrogatableSuspectIds: [] },
  question: {
    pendingPublic: null,
    pendingPrivate: null,
    latestStatement: null,
    interrogationOptions: [],
    selectedSuspectId: null,
    selectedTopicId: null,
    selectedSuspectLeverage: 0,
    spendLeverage: false,
    selectedResponseId: null,
    blockedSnitchPlayerIds: [],
  },
  evidence: { heldEvidence: [], knownCaseCards: [], latestSearch: null },
  accusation: {
    options: { suspects: [], weapons: [], motives: [] },
    selectedSuspectId: null,
    selectedWeaponId: null,
    selectedMotiveId: null,
    solveAttempt: null,
    finalGuess: null,
  },
  history: {
    entries: [{ type: "case_opened", actorName: "Case file" }],
    lastEvent: "Case opened",
    commandError: null,
    commandStatus: false,
    retryAvailable: false,
  },
  chisel: null,
}

describe("CasebookWorkspace", () => {
  it("routes the selected public history page", () => {
    render(CasebookWorkspace, { page: "history", view: baseView, actions: noActions })
    expect(document.querySelector("#public-case-history")).toHaveTextContent("case opened")
  })

  it("does not render Chisel data in a Detective view", () => {
    render(CasebookWorkspace, { page: "chisel", view: baseView, actions: noActions })
    expect(document.querySelector("#chisel-casebook-page")).not.toBeInTheDocument()
    expect(screen.queryByText(/most useful/i)).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and verify missing module failure**

Run: `rtk npm run test:ui -- assets/svelte/game/CasebookWorkspace.test.js`

Expected: FAIL because `CasebookWorkspace.svelte` does not exist.

- [ ] **Step 3: Build an allow-listed view model in GameBook**

Define `casebookView` with `$derived.by`. Copy only fields currently read by
the six casebook page branches. Build `chisel` as follows:

```javascript
const chiselView =
  privateState.role === "chisel"
    ? {
        identity: chisel,
        pendingInterrogation: pendingPrivate,
        selectedResponseId,
        casebook: privateState.casebook ?? null,
        leverageByDetective: privateState.leverage_by_detective ?? {},
      }
    : null
```

Convert `availableActions` from `Set` to an array before passing it. Pass only
the current browser's private projection fields; never merge Chisel and
Detective fixtures.

- [ ] **Step 4: Move existing page sections into the workspace**

Move the complete existing DOM subtrees identified by these stable IDs from
`GameBook.svelte` into `CasebookWorkspace.svelte`:

- `#casebook-action-page` search content becomes the `page === "search"` branch.
- `#interrogation-workspace` becomes the `page === "question"` branch.
- `#private-evidence-dossier` becomes the `page === "evidence"` branch.
- `#accusation-sheet` and `#case-closed-result` become the `page === "accusation"` branch.
- `#public-case-history` becomes the `page === "history"` branch.
- `#chisel-casebook-page` becomes the guarded `page === "chisel" && view.role === "chisel" && view.chisel` branch.

Replace direct state mutations with the named `actions` callbacks. Keep every
existing fieldset, label, button ID, radio name, alert/status role, and disabled
condition. No Channel call is allowed in this component. During this task,
render `CasebookWorkspace` as the existing `CasebookDrawer` child so the app
continues compiling before Task 8 replaces the drawer shell.

- [ ] **Step 5: Run workspace and existing interaction tests**

Run: `rtk npm run test:ui -- assets/svelte/game/CasebookWorkspace.test.js`

Expected: PASS.

Run: `rtk npm run test:ui && rtk mix assets.build`

Expected: all current UI tests and both Vite builds pass.

- [ ] **Step 6: Commit**

```bash
rtk git add assets/svelte/game/CasebookWorkspace.svelte assets/svelte/game/CasebookWorkspace.test.js assets/svelte/GameBook.svelte
rtk git commit -m "refactor(game): extract casebook pages"
```

### Task 7: Extract blocking pause and reconnect state

**Files:**
- Create: `assets/svelte/game/PauseCurtain.svelte`
- Create: `assets/svelte/game/PauseCurtain.test.js`
- Modify: `assets/css/app.css`

**Interfaces:**
- Consumes: `active`, `reason`, `offlinePlayers`, `canResume`, `commandPending`, `commandError`, `onResume`.
- Produces: `#game-pause-curtain`, `#paused-player-list`, and `#resume-game`.
- Never owns Presence membership or sends a Channel command directly.

- [ ] **Step 1: Write failing pause tests**

```javascript
import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"
import PauseCurtain from "./PauseCurtain.svelte"

describe("PauseCurtain", () => {
  it("shows offline players and exposes resume only to authority", async () => {
    const onResume = vi.fn()
    render(PauseCurtain, {
      active: true,
      reason: "Detective disconnected",
      offlinePlayers: [{ id: "d1", display_name: "Marlowe" }],
      canResume: true,
      commandPending: false,
      commandError: null,
      onResume,
    })

    expect(screen.getByRole("dialog", { name: "Case paused" })).toHaveTextContent("Marlowe")
    await fireEvent.click(screen.getByRole("button", { name: "Resume game" }))
    expect(onResume).toHaveBeenCalledTimes(1)
  })

  it("renders nothing while inactive", () => {
    render(PauseCurtain, {
      active: false,
      reason: null,
      offlinePlayers: [],
      canResume: false,
      commandPending: false,
      commandError: null,
      onResume: vi.fn(),
    })
    expect(screen.queryByRole("dialog", { name: "Case paused" })).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and verify missing module failure**

Run: `rtk npm run test:ui -- assets/svelte/game/PauseCurtain.test.js`

Expected: FAIL because `PauseCurtain.svelte` does not exist.

- [ ] **Step 3: Move pause presentation into the component**

Move the existing pause seal document, reason, offline ledger, provenance,
command error, and resume button from `GameBook` into `PauseCurtain`. Preserve
dialog labeling and make the backdrop block pointer and keyboard interaction.
Only render the resume button when `canResume`; otherwise show waiting copy.

- [ ] **Step 4: Run pause tests**

Run: `rtk npm run test:ui -- assets/svelte/game/PauseCurtain.test.js`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add assets/svelte/game/PauseCurtain.svelte assets/svelte/game/PauseCurtain.test.js assets/css/app.css
rtk git commit -m "refactor(game): extract pause curtain"
```

### Task 8: Integrate the authoritative full-screen table in GameBook

**Files:**
- Modify: `assets/svelte/GameBook.svelte`
- Modify: `assets/css/app.css`
- Delete: `assets/svelte/game/PlayerHUD.svelte`
- Delete: `assets/svelte/game/PlayerHUD.test.js`
- Delete: `assets/svelte/game/ActionDock.svelte`
- Delete: `assets/svelte/game/ActionDock.test.js`
- Delete: `assets/svelte/game/CasebookDrawer.svelte`
- Delete: `assets/svelte/game/CasebookDrawer.test.js`
- Modify: `test/detective_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: all components from Tasks 1-7.
- Produces: local `activeAction` and `effectiveLegalLocationIds` without changing server projections.
- Preserves: every Channel topic, event handler, command envelope, retry ID, projection sync, Presence reconciliation, and role-specific page.

- [ ] **Step 1: Add a failing projection allow-list assertion**

Extend `game_live_test.exs` for a Detective game render:

```elixir
component = get_svelte(view, id: "game-frontend")
private = component.props["initial_private"]
public = component.props["initial_public"]

refute Map.has_key?(public, "solution")
refute Map.has_key?(private, "response_options")
refute Map.has_key?(private, "chisel_notes")
assert is_list(private["available_actions"])
```

- [ ] **Step 2: Run the focused LiveView test**

Run: `rtk mix test test/detective_web/live/game_live_test.exs`

Expected: PASS before refactor; this is a characterization gate.

- [ ] **Step 3: Add local action mode without adding authority**

Add:

```javascript
let activeAction = $state(null)

let effectiveLegalLocationIds = $derived(
  activeAction === "place" || activeAction === "move" ? legalLocationIds : [],
)

function chooseActionMode(action) {
  if (commandPending || !controlsReady || !availableActions.has(action)) return
  activeAction = activeAction === action ? null : action
  mapSelection = null
}
```

Update `selectMapLocation` to return unless `activeAction` equals the projected
selection type. Clear `activeAction`, `mapSelection`, and `mapIntent` when a new
private projection removes that action. After an authoritative location update,
clear mode and selection. Do not change `sendCommand`.

Add this guard inside `applyPrivate` after assigning the new state:

```javascript
const nextActions = new Set(nextState.available_actions ?? [])
if (activeAction && !nextActions.has(activeAction)) {
  activeAction = null
  mapSelection = null
  mapIntent = null
}
```

Start `mapStatus` with `Choose Place` or `Choose Move` when the action is
available but no mode is selected. Never describe a red-ringed destination
until `effectiveLegalLocationIds` is non-empty.

- [ ] **Step 4: Compose the extracted surfaces**

Replace the outer open-book structure with `GameTableShell`. Pass:

- `DetectiveRail`: public Detective rows, current ID, own ID, narrow private
  resources, Presence data, and countdown label.
- `ChiselConsole`: public Chisel row and Chisel-only props guarded by
  `privateState.role === "chisel"`.
- `MapStage`: `effectiveLegalLocationIds`, public tokens, preview, pending ID,
  latest travel, and `disabled={!controlsReady || commandPending}`.
- `ContextStack`: movement preview and command message.
- `ActionRail`: exact available actions, active mode, and existing callbacks.
- `CasebookOverlay`: `CasebookWorkspace` as its child content, with the
  allow-listed `casebookView` and callback object from Task 6.
- `PauseCurtain`: existing pause assign data and `sendCommand("resume", {})` callback.

Move casebook page tabs out of the map surface. `handleDockAction` keeps the same
behavior: direct server actions call `sendCommand`, while Question and
Accusation open their authorized dossier page.

Initialize `drawerOpen` to `false`. Add one `Casebook` physical key to the
action rail that opens the current role's first authorized page without sending
a command. Search, Question, Evidence, Accusation, History, and Chisel-specific
actions may still open their exact page directly.

- [ ] **Step 5: Remove replaced components and obsolete CSS**

Delete `PlayerHUD`, `ActionDock`, and `CasebookDrawer` only after the new
components compile and their replacement tests pass. Remove `.player-hud-*`,
`.action-dock-*`, `.casebook-drawer-*`, and `#open-casebook` rules that no
longer have a runtime consumer. Keep map, pause, and motion rules still used by
the new components. Remove the temporary legacy `PlayerHUD` and `ActionDock`
calls from `CasebookWorkspace` before deleting their modules; HUD and actions
must render only in the table shell.

- [ ] **Step 6: Run all UI tests**

Run: `rtk npm run test:ui`

Expected: all replacement and retained map tests pass; deleted test files are no longer discovered.

- [ ] **Step 7: Run Phoenix regressions**

Run: `rtk mix test test/detective_web/live/game_live_test.exs test/detective_web/channels/game_channel_test.exs test/detective/games/projections_test.exs test/detective/games/engine_test.exs`

Expected: PASS with unchanged rules, Channel authorization, and secret boundaries.

- [ ] **Step 8: Commit**

```bash
rtk git add assets/svelte/GameBook.svelte assets/svelte/game assets/css/app.css test/detective_web/live/game_live_test.exs
rtk git commit -m "refactor(game): compose full-screen table"
```

### Task 9: Verify responsive play, motion, and realtime failures

**Files:**
- Modify when required by observed defects: `assets/css/app.css`
- Modify when required by observed defects: `assets/svelte/GameBook.svelte`
- Modify when required by observed defects: focused components from Tasks 1-7

**Interfaces:**
- Consumes: complete full-screen table from Tasks 1-8.
- Produces: browser-verified authoritative gameplay at desktop, tablet, landscape mobile, portrait guidance, keyboard, and reduced motion.

- [ ] **Step 1: Add responsive and reduced-motion CSS**

Implement these exact layout transitions:

```css
@media (max-width: 63.999rem) {
  .noir-game-detective-rail { left: 0.75rem; right: 0.75rem; top: auto; bottom: 5.75rem; translate: 0 0; }
  .noir-game-chisel { right: 0.75rem; top: 0.75rem; max-width: min(17rem, 55vw); }
  .noir-game-context { left: 0.75rem; right: 0.75rem; top: auto; bottom: 10rem; }
  .noir-game-actions { bottom: 0.75rem; width: calc(100% - 1.5rem); overflow-x: auto; }
}

@media (orientation: portrait) and (max-width: 40rem) {
  .noir-map-rotate-notice { display: grid; }
}

@media (prefers-reduced-motion: reduce) {
  .map-detective-token,
  .map-travel-line,
  .map-arrival-pulse,
  .map-legal-ring,
  .noir-paper-sheet,
  .noir-casebook-dialog {
    animation: none !important;
    transition-duration: 0.01ms !important;
  }
}
```

Add a portrait rotate notice that does not block casebook, public status,
history, or reconnect controls.

- [ ] **Step 2: Run automated gates**

Run: `rtk npm run test:ui`

Expected: all tests pass.

Run: `rtk mix assets.build`

Expected: client and SSR builds pass without warnings.

Run: `rtk mix precommit`

Expected: all project checks pass.

- [ ] **Step 3: Invoke the Playwright skill for multi-context acceptance**

Use independent authenticated Chisel and Detective browser contexts. Verify at
1440x900, 1024x768, 844x390, and 390x844:

1. The official map fills the gameplay viewport.
2. Four Detective slots remain on the left or compact bottom rail.
3. Chisel stays separate in the upper-right.
4. Move hotspots are absent before Move mode selection.
5. Selecting Move enables only projected legal hotspots.
6. Clicking a hotspot changes only local preview and opens ContextStack.
7. Cancel clears preview without a command.
8. Confirm sends one command with the current expected version.
9. Token and AP change only after the authoritative projection.
10. Inactive Detective and Chisel cannot select Move.
11. Search, Question, Evidence, Accusation, History, and Chisel pages open in the overlay.
12. Stale state refreshes projections before interaction returns.
13. Timeout retries the same command ID.
14. Disconnect removes hotspot semantics immediately.
15. Pause blocks underlying interaction; authorized resume works.
16. Keyboard and reduced-motion paths preserve the same information.
17. Browser console contains zero warnings and errors.

- [ ] **Step 4: Fix each observed defect test-first**

Add a focused Vitest assertion for component behavior or an ExUnit assertion
for projection behavior, verify failure, apply the smallest fix, then rerun the
focused test. Never weaken a server rule or projection boundary to satisfy a
visual test.

- [ ] **Step 5: Run final gates**

Run: `rtk npm run test:ui && rtk mix precommit`

Expected: both pass.

- [ ] **Step 6: Commit verified polish**

```bash
rtk git add assets/css/app.css assets/svelte/GameBook.svelte assets/svelte/game/GameTableShell.svelte assets/svelte/game/GameTableShell.test.js assets/svelte/game/DetectiveRail.svelte assets/svelte/game/ChiselConsole.svelte assets/svelte/game/GameHud.test.js assets/svelte/game/MapStage.svelte assets/svelte/game/MapStage.test.js assets/svelte/game/GameBoard.svelte assets/svelte/game/GameBoard.test.js assets/svelte/game/ContextStack.svelte assets/svelte/game/ContextStack.test.js assets/svelte/game/ActionRail.svelte assets/svelte/game/ActionRail.test.js assets/svelte/game/CasebookOverlay.svelte assets/svelte/game/CasebookOverlay.test.js assets/svelte/game/CasebookWorkspace.svelte assets/svelte/game/CasebookWorkspace.test.js assets/svelte/game/PauseCurtain.svelte assets/svelte/game/PauseCurtain.test.js test/detective_web/live/game_live_test.exs
rtk git diff --cached --name-only
rtk git commit -m "fix(game): polish full-screen table"
```

Before committing, unstage unrelated files. If acceptance finds no defect and
no tracked file changes, skip this commit.
