# Cinematic Map and Action System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a graphics-first *Detective: City of Angels* board with the official artwork, a server-owned 100-location Classic topology, strict Classic setup, and authoritative click-select-confirm actions.

**Architecture:** Phoenix owns board topology, legal actions, commands, persistence, and public/private projections. LiveSvelte renders the official board as an inert background plus a transparent interaction layer; focused Svelte components receive explicit server-projected data and emit intent events back to `GameBook.svelte`. The existing authenticated game route and channel topics remain unchanged.

**Tech Stack:** Elixir 1.17+, Phoenix 1.8.9, Ecto/PostgreSQL, Phoenix Channels, LiveSvelte 0.18, Svelte 5, Tailwind CSS 4, Vite 8, Vitest, Testing Library, Playwright.

## Global Constraints

- Run every shell command through `rtk`.
- Use `apply_patch` for text edits; preserve untracked `.agents/`, `.superpowers/`, `output/`, and `skills-lock.json`.
- Keep Phoenix as the sole game authority; never mutate AP, location, phase, winner, challenge result, or secret data optimistically.
- Keep the game route in the existing `live_session :require_authenticated_user` and pass `current_scope`; no router change belongs in this plan.
- Use exactly one Chisel and two to four Detectives for Classic start.
- Default remaining Days are 9, 8, and 7 for two, three, and four Detectives; a positive case `max_days` override wins.
- First placement is free at a Police Station; Move costs one AP and requires at least one shared district.
- Use the official full-board image as a local asset with non-commercial attribution; do not hotlink it.
- Use IBM Plex Serif, Sans, and Mono only; do not add another display font.
- Maintain Tailwind 4 imports, write no `@apply`, add no inline raw script, and keep app bundles under `app.js` and `app.css`.
- Only legal hotspots may be focusable or clickable. Support keyboard, touch targets of at least 44 CSS pixels, and `prefers-reduced-motion`.
- Public and Detective projections must never contain Chisel casebook secrets.
- Use TDD for every behavior change and commit only task-owned files after its reviewer gate.

## File Structure

### Server and data

- Create `lib/detective/cases/board_catalog.ex`: compile-time loader and lookup API for canonical boards.
- Create `priv/board/dcoa_classic.json`: the five districts and 100 numbered Classic locations.
- Create `test/detective/cases/board_catalog_test.exs`: catalog completeness and topology tests.
- Create `test/detective/cases/board_asset_test.exs`: local asset provenance and checksum test.
- Modify `lib/detective/cases/validator.ex`: resolve topology through `board_id`.
- Modify `lib/detective/cases/search_deck.ex`: validate search keys against the resolved catalog.
- Modify `lib/detective/games/engine.ex`: initialize catalog locations and Classic Day defaults.
- Modify `lib/detective/games.ex`: enforce strict Classic player count before start persistence.
- Modify `lib/detective/games/projections/detective.ex`: gate destination IDs through `available_actions`.
- Modify `lib/detective_web/channels/lobby_channel.ex`: expose the strict setup error code.
- Modify `priv/repo/seeds.exs`: reference `dcoa_classic` and canonical location IDs.
- Modify fixtures and affected tests to reference the board catalog instead of inline fictional topology.

### Assets and Svelte

- Create `assets/public/images/maps/dcoa/game-board-final.png`: official 1000x636 board artwork.
- Create `assets/public/images/maps/dcoa/source.json`: source, rights, dimensions, and checksum.
- Create `assets/public/images/maps/dcoa/ATTRIBUTION.md`: visible fan-project attribution policy.
- Create `assets/svelte/game/GameBoard.svelte`: board image, hotspots, tokens, fallback list, and travel transition.
- Create `assets/svelte/game/PlayerHUD.svelte`: D1-D4 and rightmost Chisel dossier strip.
- Create `assets/svelte/game/ActionDock.svelte`: server-driven actions and movement confirmation slip.
- Create `assets/svelte/game/CasebookDrawer.svelte`: desktop drawer and mobile bottom-sheet shell.
- Create `assets/svelte/game/GameBoard.test.js`, `PlayerHUD.test.js`, `ActionDock.test.js`, and `CasebookDrawer.test.js`.
- Create `assets/test/setup.js` and `vitest.config.mjs`: Svelte component test harness.
- Modify `assets/svelte/GameBook.svelte`: orchestration, command transport, projection reconciliation, and component composition only.
- Modify `assets/css/app.css`: focused board/HUD/drawer states and reduced-motion rules without `@apply`.
- Modify `package.json` and `package-lock.json`: Vitest and Testing Library development dependencies plus `test:ui`.

### Acceptance evidence

- Create `docs/qa/2026-08-04-cinematic-map-actions.md`: exact browser scenarios, viewport results, console result, and final verification commands.

---

### Task 1: Vendor the official board with provenance

**Files:**
- Create: `assets/public/images/maps/dcoa/game-board-final.png`
- Create: `assets/public/images/maps/dcoa/source.json`
- Create: `assets/public/images/maps/dcoa/ATTRIBUTION.md`
- Create: `test/detective/cases/board_asset_test.exs`

**Interfaces:**
- Consumes: Van Ryder Games CDN asset URL from the approved design.
- Produces: stable runtime URL `/images/maps/dcoa/game-board-final.png` and checksum `9cb4b980b6b5a4567315aca2ab82e276f50dc403febcabd806e249672a74c61b`.

- [ ] **Step 1: Write the failing provenance test**

```elixir
defmodule Detective.Cases.BoardAssetTest do
  use ExUnit.Case, async: true

  @asset Path.expand("../../../assets/public/images/maps/dcoa/game-board-final.png", __DIR__)
  @metadata Path.expand("../../../assets/public/images/maps/dcoa/source.json", __DIR__)

  test "official board asset matches recorded non-commercial provenance" do
    metadata = @metadata |> File.read!() |> Jason.decode!()
    digest = @asset |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    assert metadata["source_url"] ==
             "https://vanrydergames.com/cdn/shop/files/GameBoard_FINAL_069e54c3-3406-4bd3-9589-1fe30dee505f.png?v=1717096238"

    assert metadata["project_use"] == "public_non_commercial_fan_project"
    assert metadata["width"] == 1000
    assert metadata["height"] == 636
    assert metadata["sha256"] == digest
    assert digest == "9cb4b980b6b5a4567315aca2ab82e276f50dc403febcabd806e249672a74c61b"
  end
end
```

- [ ] **Step 2: Run the test and confirm the asset is absent**

Run: `rtk mix test test/detective/cases/board_asset_test.exs`

Expected: FAIL from `File.read!/1` because the local asset or metadata file does not exist.

- [ ] **Step 3: Download the exact approved publisher asset**

```bash
rtk mkdir -p assets/public/images/maps/dcoa
rtk curl -L --fail --output assets/public/images/maps/dcoa/game-board-final.png 'https://vanrydergames.com/cdn/shop/files/GameBoard_FINAL_069e54c3-3406-4bd3-9589-1fe30dee505f.png?v=1717096238'
rtk shasum -a 256 assets/public/images/maps/dcoa/game-board-final.png
```

Expected checksum: `9cb4b980b6b5a4567315aca2ab82e276f50dc403febcabd806e249672a74c61b`.

- [ ] **Step 4: Add exact metadata and attribution**

`source.json` must contain:

```json
{
  "title": "Detective: City of Angels full game board",
  "publisher": "Van Ryder Games",
  "artist_credit": "Vincent Dutrait; based on the 1932 K. M. Leuschner map",
  "source_url": "https://vanrydergames.com/cdn/shop/files/GameBoard_FINAL_069e54c3-3406-4bd3-9589-1fe30dee505f.png?v=1717096238",
  "publisher_page": "https://vanrydergames.com/collections/dcoa",
  "base_map_record": "https://www.loc.gov/item/2006626011/",
  "project_use": "public_non_commercial_fan_project",
  "rights_note": "Unofficial fan project. Not affiliated with or endorsed by Van Ryder Games. Commercial use is outside the approved project scope.",
  "downloaded_at": "2026-08-04",
  "sha256": "9cb4b980b6b5a4567315aca2ab82e276f50dc403febcabd806e249672a74c61b",
  "width": 1000,
  "height": 636
}
```

`ATTRIBUTION.md` must repeat the publisher, artist/base-map credit, source URL,
non-commercial status, non-affiliation notice, and replacement/permission
requirement before any future monetization.

- [ ] **Step 5: Verify and commit the asset boundary**

Run: `rtk mix test test/detective/cases/board_asset_test.exs`

Expected: `1 test, 0 failures`.

```bash
rtk git add assets/public/images/maps/dcoa test/detective/cases/board_asset_test.exs
rtk git commit -m "chore(assets): vendor official game board"
```

### Task 2: Add the canonical 100-location board catalog

**Files:**
- Create: `priv/board/dcoa_classic.json`
- Create: `lib/detective/cases/board_catalog.ex`
- Create: `test/detective/cases/board_catalog_test.exs`

**Interfaces:**
- Consumes: board ID `"dcoa_classic"`.
- Produces: `Detective.Cases.BoardCatalog.fetch/1`, `locations/1`, and `location/2` returning decoded string-key maps.

- [ ] **Step 1: Write catalog completeness and topology tests**

```elixir
defmodule Detective.Cases.BoardCatalogTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.BoardCatalog

  test "Classic catalog contains every numbered board location once" do
    assert {:ok, board} = BoardCatalog.fetch("dcoa_classic")
    numbers = Enum.map(board["locations"], & &1["number"])

    assert board["district_ids"] ==
             ~w(westside hollywood central_la san_gabriel_valley south_bay)

    assert length(board["locations"]) == 100
    assert Enum.sort(numbers) == Enum.to_list(1..100)
    assert Enum.uniq(numbers) == numbers
  end

  test "locations carry valid movement and rendering data" do
    assert {:ok, locations} = BoardCatalog.locations("dcoa_classic")

    assert Enum.all?(locations, fn location ->
             location["type"] in ~w(standard police_station mob_joint) and
               location["district_ids"] != [] and
               Enum.all?(location["district_ids"], &is_binary/1) and
               is_number(location["x"]) and location["x"] >= 0.0 and location["x"] <= 1.0 and
               is_number(location["y"]) and location["y"] >= 0.0 and location["y"] <= 1.0
           end)

    assert {:ok, headquarters} = BoardCatalog.location("dcoa_classic", "51")
    assert headquarters["number"] == 51
    assert headquarters["type"] == "police_station"
    assert "central_la" in headquarters["district_ids"]

    assert {:error, :unknown_board} = BoardCatalog.fetch("unknown")
    assert {:error, :unknown_location} = BoardCatalog.location("dcoa_classic", "101")
  end
end
```

- [ ] **Step 2: Run the catalog test and confirm the module is missing**

Run: `rtk mix test test/detective/cases/board_catalog_test.exs`

Expected: compilation FAIL because `Detective.Cases.BoardCatalog` is undefined.

- [ ] **Step 3: Create the compile-time catalog loader**

```elixir
defmodule Detective.Cases.BoardCatalog do
  @moduledoc "Loads immutable server-owned board topology."

  @catalog_path :detective
                |> :code.priv_dir()
                |> List.to_string()
                |> Path.join("board/dcoa_classic.json")
  @external_resource @catalog_path
  @catalog @catalog_path |> File.read!() |> Jason.decode!()
  @catalog_id @catalog["id"]

  def fetch(@catalog_id), do: {:ok, @catalog}
  def fetch(_board_id), do: {:error, :unknown_board}

  def locations(board_id) do
    with {:ok, board} <- fetch(board_id), do: {:ok, board["locations"]}
  end

  def location(board_id, location_id) when is_binary(location_id) do
    with {:ok, locations} <- locations(board_id),
         %{} = location <- Enum.find(locations, &(&1["id"] == location_id)) do
      {:ok, location}
    else
      nil -> {:error, :unknown_location}
      {:error, reason} -> {:error, reason}
    end
  end

  def location(_board_id, _location_id), do: {:error, :unknown_location}
end
```

- [ ] **Step 4: Populate the canonical data file from the official City Planner**

The JSON top level has `id: "dcoa_classic"`, the ordered five-value
`district_ids` list asserted by the test, and a `locations` array. The committed
array must contain all 100 records transcribed from `CityPlanner.pdf`. Every
record contains these exact fields and constraints:

| Field | Constraint |
| --- | --- |
| `id` | Printed number as a string, `"1"` through `"100"` |
| `number` | Matching integer, `1` through `100` |
| `slug` | Unique kebab-case landmark slug |
| `name` | Printed board landmark name |
| `type` | `standard`, `police_station`, or `mob_joint` |
| `district_ids` | Every applicable stable district ID |
| `x` | Normalized horizontal center in the full 1000x636 board plane |
| `y` | Normalized vertical center in the full 1000x636 board plane |

Validate special blue Police Stations and orange Mob Joints against both the
planner and full-board image. Do not infer movement from nearby roads.

- [ ] **Step 5: Run tests and inspect the data diff**

```bash
rtk mix test test/detective/cases/board_catalog_test.exs
rtk git diff --check
rtk git diff --stat
```

Expected: catalog tests PASS; the data diff contains exactly 100 location objects.

- [ ] **Step 6: Commit the catalog**

```bash
rtk git add priv/board/dcoa_classic.json lib/detective/cases/board_catalog.ex test/detective/cases/board_catalog_test.exs
rtk git commit -m "feat(cases): add classic board catalog"
```

### Task 3: Make cases reference the canonical board

**Files:**
- Modify: `lib/detective/cases/validator.ex:1-120`
- Modify: `lib/detective/cases/search_deck.ex:1-100`
- Modify: `lib/detective/games/engine.ex:1-80,1285-1335`
- Modify: `priv/repo/seeds.exs:65-140,320-440`
- Modify: `test/support/fixtures/cases_fixtures.ex:20-145`
- Modify: `test/detective/cases/validator_test.exs`
- Modify: affected engine, projection, runtime, channel, and LiveView tests containing fictional location IDs.

**Interfaces:**
- Consumes: `BoardCatalog.locations(board_id)`.
- Produces: case definition field `"board_id" => "dcoa_classic"`; runtime `State.locations` still uses normalized atom-key location maps keyed by numeric string ID.

- [ ] **Step 1: Add failing validator coverage for board references**

```elixir
test "requires a known board and validates suspect/search location references" do
  content = valid_case_definition() |> Map.delete("locations")

  assert {:error, :unknown_board} = Validator.validate(Map.put(content, "board_id", "missing"))
  assert :ok = Validator.validate(Map.put(content, "board_id", "dcoa_classic"))

  invalid_suspect = put_in(content, ["suspects", Access.at(0), "location_id"], "101")
  assert {:error, :invalid_suspect_location} =
           Validator.validate(Map.put(invalid_suspect, "board_id", "dcoa_classic"))
end
```

- [ ] **Step 2: Run focused tests and confirm inline locations are still required**

Run: `rtk mix test test/detective/cases/validator_test.exs`

Expected: FAIL with `:invalid_locations` or mismatched `:unknown_board` behavior.

- [ ] **Step 3: Resolve locations once in Validator and SearchDeck**

Use this flow in `Validator.validate/1`:

```elixir
with {:ok, locations} <- BoardCatalog.locations(case_definition["board_id"]),
     :ok <- validate_locations(locations),
     :ok <- validate_unique_location_ids(locations),
     :ok <- validate_police_station(locations),
     :ok <- validate_three_move_reachability(locations),
     :ok <- validate_suspect_locations(case_definition["suspects"], locations),
     :ok <- ResponseMatrix.validate(case_definition),
     :ok <- SearchDeck.validate(case_definition, locations),
     :ok <- AccusationSheet.validate(case_definition) do
  :ok
end
```

Change `SearchDeck.validate/1` to resolve through `BoardCatalog`, then delegate
to a new public `validate/2` accepting the already-resolved location list. This
keeps standalone validation and avoids duplicate topology rules.

- [ ] **Step 4: Initialize Engine locations from the board catalog**

Replace `normalize_locations(case_definition["locations"])` with:

```elixir
with [chisel] <- chisels,
     true <- length(detectives) in 2..4,
     :ok <- Validator.validate(case_definition),
     {:ok, board_locations} <- BoardCatalog.locations(case_definition["board_id"]),
     {:ok, locations} <- normalize_locations(board_locations),
     true <- Enum.any?(locations, fn {_id, location} -> location.type == "police_station" end) do
```

Add `BoardCatalog` to the existing Cases alias list.

- [ ] **Step 5: Remap seed and fixture IDs**

Remove inline `"locations"` arrays and add `"board_id" => "dcoa_classic"`.
Use this exact test mapping consistently:

```text
central-precinct -> 51
archive          -> 48
canal-gate       -> 82
harbor-precinct  -> 84
pier-club        -> 96
```

Place the test Night Clerk at `51`, its location search result at `51`, and the
sample production suspects/search results at canonical IDs matching their
intended districts. Update command payloads and assertions, not event types or
authorization expectations.

- [ ] **Step 6: Run the affected server suite**

```bash
rtk mix test test/detective/cases/validator_test.exs test/detective/games/engine_test.exs test/detective/games/projections_test.exs
rtk mix test test/detective/games/runtime_test.exs test/detective_web/channels/game_channel_test.exs test/detective_web/live/game_live_test.exs
```

Expected: all selected tests PASS with catalog-backed locations.

- [ ] **Step 7: Commit the case/catalog integration**

```bash
rtk git add lib/detective/cases/validator.ex lib/detective/cases/search_deck.ex lib/detective/games/engine.ex priv/repo/seeds.exs test/support/fixtures/cases_fixtures.ex test/detective/cases/validator_test.exs test/detective/games/engine_test.exs test/detective/games/projections_test.exs test/detective/games/runtime_test.exs test/detective/games/snapshot_codec_test.exs test/detective_web/channels/game_channel_test.exs test/detective_web/live/game_live_test.exs
rtk git diff --cached --check
rtk git commit -m "refactor(cases): reference board catalog"
```

### Task 4: Enforce strict Classic setup and Day defaults

**Files:**
- Modify: `lib/detective/games.ex:178-450`
- Modify: `lib/detective/games/engine.ex:10-80`
- Modify: `lib/detective_web/channels/lobby_channel.ex:90-130`
- Modify: `test/detective/games/runtime_test.exs`
- Modify: `test/detective/games/engine_test.exs`
- Modify: `test/detective_web/channels/lobby_channel_test.exs`
- Modify: success helpers that start a game with only one Detective.

**Interfaces:**
- Consumes: active lobby players and optional positive `case_definition["max_days"]`.
- Produces: `:not_enough_detectives`, strict two-to-four start, and 9/8/7 `days_remaining` defaults.

- [ ] **Step 1: Write failing strict-start tests**

```elixir
test "Classic start requires at least two ready Detectives" do
  host = user_fixture()
  detective = user_fixture()
  %{game: game, invite_token: token} = game_fixture(host)
  assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)
  assert {:ok, %{lobby: lobby}} = Games.set_ready(Scope.for_user(detective), game.id, 0, true)

  assert {:error, :not_enough_detectives} =
           Games.start_game(Scope.for_user(host), game.id, Ecto.UUID.generate(), lobby.current_version)

  assert detective.id
end
```

Add table-driven Engine coverage:

```elixir
for {detective_count, expected_days} <- [{2, 9}, {3, 8}, {4, 7}] do
  test "#{detective_count} Detectives start with #{expected_days} Days" do
    count = unquote(detective_count)
    expected = unquote(expected_days)
    assert {:ok, state} =
             Engine.new(game(), classic_players(count), Map.delete(case_definition(), "max_days"))

    assert state.days_remaining == expected
  end
end

test "positive case max_days overrides the Classic default" do
  assert {:ok, state} =
           Engine.new(game(), classic_players(2), Map.put(case_definition(), "max_days", 5))

  assert state.days_remaining == 5
end
```

Add this local helper beside `players/0`:

```elixir
defp classic_players(count) do
  detectives =
    for seat <- 1..count do
      %{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        display_name: "Detective #{seat}",
        role: "detective",
        seat: seat
      }
    end

  [
    %{
      id: Ecto.UUID.generate(),
      user_id: Ecto.UUID.generate(),
      display_name: "Chisel",
      role: "chisel",
      seat: nil
    }
    | detectives
  ]
end
```

- [ ] **Step 2: Run focused tests and confirm one-Detective start still succeeds**

Run: `rtk mix test test/detective/games/runtime_test.exs test/detective/games/engine_test.exs`

Expected: new strict setup/default-Day assertions FAIL.

- [ ] **Step 3: Enforce lobby count before readiness**

In the `:players` transaction step, use:

```elixir
cond do
  length(chisels) != 1 -> {:error, :invalid_chisel_count}
  length(detectives) < 2 -> {:error, :not_enough_detectives}
  length(detectives) > 4 -> {:error, :too_many_detectives}
  Enum.any?(detectives, &(not &1.ready)) -> {:error, :detectives_not_ready}
  true -> {:ok, players}
end
```

Expose `not_enough_detectives` and `too_many_detectives` from
`LobbyChannel.error_code/1`.

- [ ] **Step 4: Apply the Classic Day table in Engine**

```elixir
@classic_days %{2 => 9, 3 => 8, 4 => 7}

default_days = Map.fetch!(@classic_days, length(detectives))
max_days = positive_integer(case_definition["max_days"], default_days)
```

Keep `state.day` as the elapsed Day counter starting at 1. The printed board
track displays `days_remaining`; existing evidence release arithmetic remains
based on elapsed `state.day`.

- [ ] **Step 5: Upgrade start-success fixtures to two Detectives**

Update `ready_game/0` and channel success setup to accept and ready two users in
version order. Preserve the existing `:detective` key for the first actor and
add `:detectives` for assertions that need both players.

- [ ] **Step 6: Run strict setup, lobby, and runtime tests**

```bash
rtk mix test test/detective/games/engine_test.exs test/detective/games/runtime_test.exs
rtk mix test test/detective_web/channels/lobby_channel_test.exs test/detective_web/channels/game_channel_test.exs
```

Expected: all selected tests PASS.

- [ ] **Step 7: Commit the Classic setup rule**

```bash
rtk git add lib/detective/games.ex lib/detective/games/engine.ex lib/detective_web/channels/lobby_channel.ex test/detective/games/engine_test.exs test/detective/games/runtime_test.exs test/detective/games/connection_monitor_test.exs test/detective_web/channels/lobby_channel_test.exs test/detective_web/channels/game_channel_test.exs test/detective_web/live/game_live_test.exs
rtk git commit -m "fix(game): enforce classic player setup"
```

### Task 5: Gate legal destination projections

**Files:**
- Modify: `lib/detective/games/projections/detective.ex:5-45`
- Modify: `test/detective/games/projections_test.exs`
- Modify: `test/detective/games/engine_test.exs`

**Interfaces:**
- Consumes: `Rules.available_actions/2`.
- Produces: destination IDs only when the matching action string is present.

- [ ] **Step 1: Write failing leakage/gating tests**

```elixir
test "movement IDs follow available actions" do
  state = state_fixture()
  active_user_id = player_user_id(state, state.current_detective_id)

  active = DetectiveProjection.render_private(state, active_user_id)
  assert "place" in active.available_actions
  assert active.placement_location_ids != []
  assert active.valid_move_location_ids == []

  paused = %{state | status: :paused, phase: :paused}
  paused_private = DetectiveProjection.render_private(paused, active_user_id)
  assert paused_private.available_actions == []
  assert paused_private.placement_location_ids == []
  assert paused_private.valid_move_location_ids == []
end
```

Add states for an inactive Detective, zero AP, and
`free_question_suspect_id`; each must project an empty move list.

- [ ] **Step 2: Run the projection test and observe stale legal IDs**

Run: `rtk mix test test/detective/games/projections_test.exs`

Expected: paused/inactive destination assertions FAIL.

- [ ] **Step 3: Compute actions once and gate both lists**

```elixir
available_actions = Rules.available_actions(state, actor_user_id)

%{
  available_actions: available_actions,
  valid_move_location_ids:
    if("move" in available_actions,
      do: state |> Rules.valid_move_destinations(player) |> Enum.map(& &1.id),
      else: []
    ),
  placement_location_ids:
    if("place" in available_actions,
      do: state |> Rules.police_stations() |> Enum.map(& &1.id),
      else: []
    )
}
```

Merge these fields into the existing projection map without changing private
evidence or interrogation payloads.

- [ ] **Step 4: Run projections and leakage coverage**

```bash
rtk mix test test/detective/games/projections_test.exs test/detective/games/engine_test.exs
rtk mix test test/detective_web/channels/game_channel_test.exs
```

Expected: all selected tests PASS.

- [ ] **Step 5: Commit projection gating**

```bash
rtk git add lib/detective/games/projections/detective.ex test/detective/games/projections_test.exs test/detective/games/engine_test.exs
rtk git commit -m "fix(game): gate legal map destinations"
```

### Task 6: Add the Svelte test harness and extract GameBoard

**Files:**
- Modify: `package.json`
- Modify: `package-lock.json`
- Create: `vitest.config.mjs`
- Create: `assets/test/setup.js`
- Create: `assets/svelte/game/GameBoard.svelte`
- Create: `assets/svelte/game/GameBoard.test.js`
- Modify: `assets/svelte/GameBook.svelte:1-180,610-850`
- Modify: `assets/css/app.css`

**Interfaces:**
- Consumes: `locations`, `detectives`, `legalLocationIds`, `selectedLocationId`, `pendingLocationId`, `lastTravel`, `disabled`, and `onSelect(location)`.
- Produces: accessible `select-location` intent through the callback; no Phoenix command and no AP mutation.

- [ ] **Step 1: Install the test-only frontend dependencies**

Run:

```bash
rtk npm install --save-dev vitest jsdom @testing-library/svelte @testing-library/jest-dom
```

Add `"test:ui": "vitest run"` to `package.json` scripts.

- [ ] **Step 2: Create the test configuration**

```javascript
// vitest.config.mjs
import { svelte } from "@sveltejs/vite-plugin-svelte"
import { defineConfig } from "vitest/config"

export default defineConfig({
  plugins: [svelte()],
  test: {
    environment: "jsdom",
    setupFiles: ["./assets/test/setup.js"],
  },
})
```

```javascript
// assets/test/setup.js
import "@testing-library/jest-dom/vitest"
import { cleanup } from "@testing-library/svelte"
import { afterEach } from "vitest"

afterEach(cleanup)
```

- [ ] **Step 3: Write failing board interaction tests**

```javascript
import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"
import GameBoard from "./GameBoard.svelte"

const locations = [
  { id: "48", name: "Bradbury Building", type: "standard", district_ids: ["central_la"], x: 0.48, y: 0.43 },
  { id: "51", name: "LAPD Headquarters", type: "police_station", district_ids: ["central_la"], x: 0.52, y: 0.50 },
]

describe("GameBoard", () => {
  it("emits only legal pointer and keyboard selections", async () => {
    const onSelect = vi.fn()
    render(GameBoard, {
      locations,
      detectives: [],
      legalLocationIds: ["51"],
      selectedLocationId: null,
      pendingLocationId: null,
      lastTravel: null,
      disabled: false,
      onSelect,
    })

    const legal = screen.getByTestId("map-hotspot-51")
    const illegal = screen.getByTestId("map-hotspot-48")
    expect(legal).toHaveAttribute("role", "button")
    expect(legal).toHaveAttribute("tabindex", "0")
    expect(illegal).not.toHaveAttribute("role")
    expect(illegal).not.toHaveAttribute("tabindex")

    await fireEvent.keyDown(legal, { key: "Enter" })
    expect(onSelect).toHaveBeenCalledWith(locations[1])
  })
})
```

- [ ] **Step 4: Run UI tests and confirm the component is missing**

Run: `rtk npm run test:ui -- assets/svelte/game/GameBoard.test.js`

Expected: FAIL because `GameBoard.svelte` does not exist.

- [ ] **Step 5: Extract the board with a narrow callback interface**

The component begins with:

```svelte
<script>
  let {
    locations,
    detectives,
    legalLocationIds,
    selectedLocationId,
    pendingLocationId,
    lastTravel,
    disabled,
    onSelect,
  } = $props()

  let legalIds = $derived(new Set(disabled ? [] : legalLocationIds))

  function select(event, location) {
    if (!legalIds.has(location.id)) return
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return
    if (event.type === "keydown") event.preventDefault()
    onSelect(location)
  }
</script>
```

Render `/images/maps/dcoa/game-board-final.png` in an SVG `viewBox="0 0 1000 636"`.
Port token/travel markup from `GameBook`, remove district-link lines, remove the
outer `role="img"`, and assign `role="button"` plus `tabindex="0"` only to legal
location groups. Give every location group
`data-testid="map-hotspot-{location.id}"` for focused component assertions. Add
an HTML list of legal destination buttons below the SVG.

In `GameBook`, replace `mapConnections`, `locationKeydown`, and the raw map
markup with `<GameBoard>` props and an `onSelect` callback that only records the
selection.

- [ ] **Step 6: Add focused board styles**

Move map marker, legal ring, token, travel, and reduced-motion selectors from
the monolith into `app.css`. Do not use `@apply`. Ensure every legal hotspot has
a 44px hit target independent of the printed location box.

- [ ] **Step 7: Run UI and asset builds**

```bash
rtk npm run test:ui -- assets/svelte/game/GameBoard.test.js
rtk mix assets.build
```

Expected: component test PASS; client and SSR builds complete without warnings.

- [ ] **Step 8: Commit the board extraction**

```bash
rtk git add package.json package-lock.json vitest.config.mjs assets/test assets/svelte/game/GameBoard.svelte assets/svelte/game/GameBoard.test.js assets/svelte/GameBook.svelte assets/css/app.css
rtk git commit -m "refactor(ui): extract interactive game board"
```

### Task 7: Add the cinematic player HUD

**Files:**
- Create: `assets/svelte/game/PlayerHUD.svelte`
- Create: `assets/svelte/game/PlayerHUD.test.js`
- Modify: `assets/svelte/GameBook.svelte`
- Modify: `assets/css/app.css`

**Interfaces:**
- Consumes: `players`, `currentDetectiveId`, `privateState`, `onlinePlayerIds`, `connectionSnapshotReceived`, and `disconnectLabel(playerId)`.
- Produces: four Detective slots followed by one rightmost Chisel dossier; presentation only.

- [ ] **Step 1: Write the failing role-resource test**

```javascript
import { render, screen } from "@testing-library/svelte"
import { expect, it } from "vitest"
import PlayerHUD from "./PlayerHUD.svelte"

it("renders four Detective slots and never invents Chisel AP or Scratch", () => {
  render(PlayerHUD, {
    players: [
      { id: "d1", role: "detective", seat: 1, display_name: "Marlowe", actions_remaining: 4, location_id: "51" },
      { id: "c1", role: "chisel", display_name: "The Chisel" },
    ],
    currentDetectiveId: "d1",
    privateState: { role: "chisel", leverage_by_detective: { d1: 2 } },
    onlinePlayerIds: ["d1", "c1"],
    connectionSnapshotReceived: true,
    disconnectLabel: () => "",
  })

  expect(screen.getAllByTestId(/detective-slot-/)).toHaveLength(4)
  expect(screen.getByTestId("chisel-slot")).toHaveTextContent("The Chisel")
  expect(screen.getByTestId("chisel-slot")).not.toHaveTextContent("AP")
  expect(screen.getByTestId("chisel-slot")).not.toHaveTextContent("Scratch")
})
```

- [ ] **Step 2: Run the test and confirm the component is missing**

Run: `rtk npm run test:ui -- assets/svelte/game/PlayerHUD.test.js`

Expected: FAIL because `PlayerHUD.svelte` does not exist.

- [ ] **Step 3: Implement role-correct dossiers**

Render D1-D4 in seat order and the Chisel last. Detective entries show portrait,
public AP/location, online state, active-turn mark, and the current user's
private Scratch/leverage only where the projection permits. Chisel shows
identity, online state, pending-response state, and Chisel-private leverage by
Detective. Use the existing generated portrait silhouettes as fallbacks.

- [ ] **Step 4: Replace the old bookmark block and verify**

```bash
rtk npm run test:ui -- assets/svelte/game/PlayerHUD.test.js
rtk mix assets.build
```

Expected: test PASS; D1-D4 plus Chisel render in client and SSR bundles.

- [ ] **Step 5: Commit the HUD**

```bash
rtk git add assets/svelte/game/PlayerHUD.svelte assets/svelte/game/PlayerHUD.test.js assets/svelte/GameBook.svelte assets/css/app.css
rtk git commit -m "feat(ui): add cinematic player HUD"
```

### Task 8: Add click-select-confirm movement in ActionDock

**Files:**
- Create: `assets/svelte/game/ActionDock.svelte`
- Create: `assets/svelte/game/ActionDock.test.js`
- Modify: `assets/svelte/GameBook.svelte:1-230`
- Modify: `assets/css/app.css`

**Interfaces:**
- Consumes: `availableActions`, `selection`, `origin`, `commandPending`, `commandError`, `connectionOnline`, `onConfirmMove`, `onCancelMove`, and `onAction`.
- Produces: one confirmation callback for the selected `place` or `move`; non-map action intents by exact action string.

- [ ] **Step 1: Write failing confirmation tests**

```javascript
import { fireEvent, render, screen } from "@testing-library/svelte"
import { expect, it, vi } from "vitest"
import ActionDock from "./ActionDock.svelte"

it("does not dispatch movement until the selected destination is confirmed", async () => {
  const onConfirmMove = vi.fn()
  const onCancelMove = vi.fn()

  render(ActionDock, {
    availableActions: ["move", "analyze", "end_turn"],
    selection: { type: "move", location: { id: "48", name: "Bradbury Building", district_ids: ["central_la"] } },
    origin: { id: "51", name: "LAPD Headquarters", district_ids: ["central_la"] },
    commandPending: false,
    commandError: null,
    connectionOnline: true,
    onConfirmMove,
    onCancelMove,
    onAction: vi.fn(),
  })

  expect(onConfirmMove).not.toHaveBeenCalled()
  await fireEvent.click(screen.getByRole("button", { name: "Confirm Move" }))
  expect(onConfirmMove).toHaveBeenCalledTimes(1)
})
```

- [ ] **Step 2: Run the test and confirm the component is missing**

Run: `rtk npm run test:ui -- assets/svelte/game/ActionDock.test.js`

Expected: FAIL because `ActionDock.svelte` does not exist.

- [ ] **Step 3: Change GameBook selection from command to intent**

Replace direct command dispatch in `locationAction/1` with:

```javascript
function selectMapLocation(location) {
  if (commandPending || connectionState !== "online") return

  if (placementLocationIds.has(location.id) && availableActions.has("place")) {
    mapSelection = { type: "place", location }
  } else if (moveLocationIds.has(location.id) && availableActions.has("move")) {
    mapSelection = { type: "move", location }
  }
}

function confirmMapMovement() {
  if (!mapSelection) return
  sendCommand(mapSelection.type, { location_id: mapSelection.location.id })
}
```

Clear `mapSelection` after an authoritative projection reaches the destination,
on Cancel, on a command error that makes the destination illegal, and on local
transport invalidation. Do not clear it merely because the push received ACK;
the projection is authoritative.

- [ ] **Step 4: Render server-driven actions**

ActionDock renders only strings in `availableActions`. Placement/Move use the
movement slip. Analyze, Kickback, End Turn, Search, Question, and Accuse call
`onAction` with the exact command/action identifier and never calculate cost.
Show `Dispatching car` while the movement command is pending.

- [ ] **Step 5: Run component and build tests**

```bash
rtk npm run test:ui -- assets/svelte/game/ActionDock.test.js assets/svelte/game/GameBoard.test.js
rtk mix assets.build
```

Expected: tests PASS; map click alone sends no command.

- [ ] **Step 6: Commit movement confirmation**

```bash
rtk git add assets/svelte/game/ActionDock.svelte assets/svelte/game/ActionDock.test.js assets/svelte/GameBook.svelte assets/css/app.css
rtk git commit -m "feat(ui): confirm map movement"
```

### Task 9: Extract the responsive casebook drawer

**Files:**
- Create: `assets/svelte/game/CasebookDrawer.svelte`
- Create: `assets/svelte/game/CasebookDrawer.test.js`
- Modify: `assets/svelte/GameBook.svelte`
- Modify: `assets/css/app.css`

**Interfaces:**
- Consumes: `open`, `title`, `onClose`, and a Svelte `children` snippet containing Search, Question, Evidence, Accusation, history, or Chisel-private pages.
- Produces: labeled desktop complementary drawer and mobile dialog-like bottom sheet; no game commands.

- [ ] **Step 1: Write failing drawer behavior tests**

```javascript
import { fireEvent, render, screen } from "@testing-library/svelte"
import { expect, it, vi } from "vitest"
import CasebookDrawer from "./CasebookDrawer.svelte"

it("labels the open casebook and exposes a close action", async () => {
  const onClose = vi.fn()
  render(CasebookDrawer, { open: true, title: "Evidence", onClose })

  expect(screen.getByRole("complementary", { name: "Evidence" })).toBeVisible()
  await fireEvent.click(screen.getByRole("button", { name: "Close casebook" }))
  expect(onClose).toHaveBeenCalledTimes(1)
})
```

- [ ] **Step 2: Run the test and confirm the component is missing**

Run: `rtk npm run test:ui -- assets/svelte/game/CasebookDrawer.test.js`

Expected: FAIL because `CasebookDrawer.svelte` does not exist.

- [ ] **Step 3: Implement one shell for every casebook page**

Use `{@render children?.()}` inside a labeled `<aside>`. On desktop, opening the
drawer changes the board workspace grid so the map shrinks and remains visible.
Below the desktop breakpoint, anchor it as a bottom sheet and retain at least
`55vh` for the map. Close restores focus to the control that opened it.

- [ ] **Step 4: Move current action-page sections into drawer snippets**

Group the existing Search, Question, Evidence, Accusation, public history, and
Chisel response UI by selected drawer page. Preserve all current element IDs
used by channel/LiveView/browser tests and keep secret content conditional on
the private role projection.

- [ ] **Step 5: Run UI tests and builds**

```bash
rtk npm run test:ui
rtk mix assets.build
```

Expected: every component test PASS; client and SSR builds are warning-free.

- [ ] **Step 6: Commit the drawer extraction**

```bash
rtk git add assets/svelte/game/CasebookDrawer.svelte assets/svelte/game/CasebookDrawer.test.js assets/svelte/GameBook.svelte assets/css/app.css
rtk git commit -m "refactor(ui): extract casebook drawer"
```

### Task 10: Harden reconnect, errors, accessibility, and reduced motion

**Files:**
- Modify: `assets/svelte/GameBook.svelte`
- Modify: `assets/svelte/game/GameBoard.svelte`
- Modify: `assets/svelte/game/ActionDock.svelte`
- Modify: component tests under `assets/svelte/game/`
- Modify: `assets/css/app.css`
- Modify: `test/detective_web/channels/game_channel_test.exs`

**Interfaces:**
- Consumes: existing channel lifecycle and public/private projection events.
- Produces: no stale interactive state after disconnect, distinct command messages, and accessible equivalent destination controls.

- [ ] **Step 1: Add failing frontend state tests**

Extend tests to assert:

```javascript
expect(screen.queryByRole("button", { name: /Bradbury Building/ })).not.toBeInTheDocument()
expect(screen.getByRole("status")).toHaveTextContent("Game state changed; map resynchronized")
```

Cover disabled/offline GameBoard, pending ActionDock, stale-version copy,
reduced-motion class behavior, and destination fallback list parity.

- [ ] **Step 2: Run the UI tests and capture the failures**

Run: `rtk npm run test:ui`

Expected: new offline/error/a11y assertions FAIL.

- [ ] **Step 3: Centralize transport invalidation**

The existing invalidation function must set all of these values together:

```javascript
connectionState = "offline"
connectionSnapshotReceived = false
onlinePlayerIds = []
offlineDeadlines = {}
allPlayersOnline = false
mapSelection = null
mapIntent = null
commandPending = false
retryCommand = null
```

Game-channel join restores transport status only. Interaction stays disabled
until a fresh public projection and matching private projection have both been
accepted.

- [ ] **Step 4: Map exact server errors to action-safe copy**

Add distinct messages for `not_your_turn`, `invalid_location`,
`destination_outside_district`, `no_actions_remaining`, `wrong_phase`,
`game_paused`, and `stale_version`. On `stale_version`, request/rejoin for fresh
projections before restoring controls. Timeout Retry must reuse the same
`command_id`.

- [ ] **Step 5: Complete accessibility and reduced-motion behavior**

Remove focus from illegal SVG groups, preserve Enter/Space activation for legal
groups, keep fallback destination buttons synchronized, expose pending/error
copy through `aria-live`, and add explicit `@media (prefers-reduced-motion:
reduce)` rules that disable token travel, pulses, drawer motion, and paper
transitions.

- [ ] **Step 6: Verify channel idempotency and leakage**

Add/retain a channel test that pushes the same movement `command_id` twice and
asserts one persisted event, one AP deduction, and the same version/delivery
result. Assert movement public payload keys exclude solution, response type,
hidden evidence, alternatives, and Chisel notes.

- [ ] **Step 7: Run focused frontend and channel suites**

```bash
rtk npm run test:ui
rtk mix test test/detective_web/channels/game_channel_test.exs test/detective/games/projections_test.exs test/detective/games/runtime_test.exs
rtk mix assets.build
```

Expected: all tests PASS and both asset builds are warning-free.

- [ ] **Step 8: Commit reconnect and accessibility hardening**

```bash
rtk git add assets/svelte/GameBook.svelte assets/svelte/game/GameBoard.svelte assets/svelte/game/GameBoard.test.js assets/svelte/game/ActionDock.svelte assets/svelte/game/ActionDock.test.js assets/svelte/game/PlayerHUD.test.js assets/svelte/game/CasebookDrawer.test.js assets/css/app.css test/detective_web/channels/game_channel_test.exs test/detective/games/projections_test.exs test/detective/games/runtime_test.exs
rtk git commit -m "fix(ui): harden authoritative map state"
```

### Task 11: Run two-context Playwright acceptance and precommit

**Files:**
- Create: `docs/qa/2026-08-04-cinematic-map-actions.md`
- Modify only if acceptance finds a scoped defect: files owned by Tasks 1-10 and their focused tests.

**Interfaces:**
- Consumes: completed server rules, projections, components, local PostgreSQL, and dev server.
- Produces: reproducible acceptance evidence and a green repository gate.

- [ ] **Step 1: Start the development dependencies**

```bash
rtk docker compose -f docker-compose.dev.yml up -d postgres
rtk mix ecto.setup
rtk mix phx.server
```

Run the Phoenix server in a persistent terminal session. Use the existing Vite
integration; do not add a second app bundle or inline script.

- [ ] **Step 2: Use the Playwright skill with independent contexts**

Create one Chisel context and two Detective contexts. Register/login all three,
create a two-Detective Classic room, accept both invites, Ready both Detectives,
and Start. Record exact test users and game ID in the QA document without
recording passwords or tokens.

- [ ] **Step 3: Verify placement and movement authority**

In the active Detective context:

1. Click a legal Police Station.
2. Assert the token and AP do not change before Confirm.
3. Confirm Place and assert AP remains 4 after the authoritative update.
4. Select a same-district location, Confirm Move, and assert AP becomes 3 only
   after the new projection.
5. Assert a cross-district location is not interactive.
6. Move through a border location and confirm the next district becomes legal
   on the following Move.

In the inactive Detective and Chisel contexts, assert no movement destination
is focusable or clickable.

- [ ] **Step 4: Verify the remaining action surface**

Complete one available Search or Question from the casebook drawer, execute
Analyze or Kickback when projected, and End Turn. Confirm the action dock never
shows a command absent from `available_actions`, Chisel private response data
appears only in the Chisel context, and Detective contexts contain no response
type or solution.

- [ ] **Step 5: Verify reconnect, keyboard, mobile, and visuals**

- Drop the active Detective channel and assert selection/hotspots clear.
- Reconnect and assert join alone does not restore actions; fresh projections do.
- Repeat selection and confirmation with Tab, Enter, and Space.
- Inspect 1440x900 and 390x844 viewports.
- Confirm the mobile map retains at least 55vh, HUD scrolls horizontally, and
  casebook opens as a bottom sheet.
- Enable reduced motion and confirm travel/drawer transitions are absent.
- Capture final screenshots and assert zero console errors or warnings.

- [ ] **Step 6: Run the full automated gate**

```bash
rtk npm run test:ui
rtk mix precommit
rtk git status --short
```

Expected: UI tests PASS; `mix precommit` compiles with warnings as errors,
formats, builds client/SSR without warnings, and passes the full ExUnit suite.
Only intentional QA documentation or scoped fixes are tracked.

- [ ] **Step 7: Write the QA ledger**

Record commit under test, date/timezone, browser, game roles, both viewports,
each acceptance result, console result, `npm run test:ui` count, `mix precommit`
count, and screenshot paths. Do not claim a scenario that was not executed.

- [ ] **Step 8: Commit acceptance evidence and any verified fix**

```bash
rtk git add docs/qa/2026-08-04-cinematic-map-actions.md
rtk git diff --cached --check
rtk git commit -m "test(game): verify cinematic map flow"
```

If acceptance required a scoped fix, stage each exact changed file explicitly
before the QA document. Before the final commit, inspect
`rtk git diff --cached --name-status` and unstage any unrelated or previously
untracked local file.
