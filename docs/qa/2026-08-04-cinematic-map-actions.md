# Cinematic map actions acceptance

## Run

- Date: 2026-08-04 15:21 +07 (`Asia/Ho_Chi_Minh`)
- Commit under test: `3491c4d`
- Browser: Chromium 150 on macOS
- Database: PostgreSQL from `docker-compose.dev.yml`
- Game: `868d0c5d-ed4d-49f9-b713-eb9f8fb980ae`
- Room: `G2VZWM`, `Signal at Midnight` version 5, two Detective seats
- Viewports: 1440x900 and 390x844

No password, login token, or invite token is recorded here.

## Roles

| Context | Account | Role |
| --- | --- | --- |
| `qa-chisel` | `qa.chisel.20260804@example.com` | Chisel / host |
| `qa-d1` | `qa.d1.20260804@example.com` | Detective |
| `qa-d2` | `qa.d2.20260804@example.com` | Detective |

All three accounts were registered through the UI, confirmed through the local Swoosh mailbox, and authenticated in independent Playwright browser sessions. Both Detectives accepted the same invitation, entered the lobby, became Ready, and the Chisel started the game. A concurrent Ready attempt correctly returned a stale-room message to one Detective; retrying against the refreshed lobby version succeeded.

## Acceptance results

### Placement and district movement

- PASS — `qa-d2` was the first active Detective. Clicking Glendale Station selected location 36 without sending a command: AP remained 4 and location remained unset.
- PASS — Confirm Placement produced authoritative version 4, location 36, with AP still 4.
- PASS — Clicking Angelus Temple only created a pending dispatch slip. Confirm Move produced version 5, location 37, and AP 3.
- PASS — Vermont & Pico was not focusable or present in the legal destination list from Angelus Temple, so a direct Hollywood-to-Central L.A. jump was unavailable.
- PASS — Hoover & Temple was legal as the shared Hollywood/Central L.A. border stop. Confirming it moved to location 38 and AP 2; only then did Vermont & Pico become legal. Confirming Vermont & Pico moved to location 39 and AP 1.
- PASS — The inactive Detective and Chisel each showed “No map destination is available for this player” and exposed no interactive movement hotspot.

### Server-projected actions and private information

- PASS — `qa-d2` executed Search Location at Vermont & Pico. AP changed from 1 to 0 after the projection; Search and Analyze disappeared, leaving End Turn as the only projected field action. End Turn rotated authority to `qa-d1`.
- PASS — `qa-d1` placed at Hollywood Station for free, moved to Hollywoodland Sign for one AP, then questioned Iona Pike about known case card A for one AP.
- PASS — The Chisel received the private leverage decision and allowed the question. The non-active Detective received the private facedown Snitch choice and passed.
- PASS — Only the Chisel response page exposed response classifications (`most useful` and `misdirection`) and the private solution. The Chisel delivered a misdirection response.
- PASS — Detective pages showed only the published statement plus Accept/Challenge controls. Searches for `misdirection` and `Solution suspect` returned no Detective matches.
- PASS — `qa-d1` challenged the statement. The server resolved it as successful and returned the most-useful statement as a private note.
- PASS — Analyze was present in `available_actions`, executed once, changed AP 2 to 1 and Scratch 5 to 6, then End Turn completed the turn. Kickback was not projected and was not rendered.

### Reconnect and keyboard

- PASS — With L.A. Library selected, explicitly disconnecting the active Detective socket cleared the selection, pending confirmation, and legal hotspots.
- PASS — Reconnecting did not reuse the stale interactive snapshot. Controls returned only after fresh public/private projections synchronized at version 18; the legal Central L.A. destinations and AP 4 then returned.
- PASS — Enter selected Hollywood Station and Space confirmed placement for `qa-d1`.
- PASS — From a focused legal hotspot, Tab moved focus to the next legal SVG hotspot (`map-hotspot-40`, Alvarado Street); Enter selected it and Space confirmed the move. The authoritative result was location 40 and AP 3.

### Responsive layout and motion

- PASS — At 390x844, `#casebook-map-page` measured 1006.91 px (119.30 vh), above the 55 vh minimum.
- PASS — The player HUD measured 372 px client width and 864 px scroll width with `overflow-x: auto`.
- PASS — The casebook drawer anchored at the viewport bottom after scrolling into view and measured 379.80 px, exactly 45.00 vh.
- PASS — With `prefers-reduced-motion: reduce`, the map token, legal ring, travel trace, and drawer all reported `animation-name: none`; transition/animation durations were limited to 0.01 ms.
- PASS — Desktop Detective and Chisel views remained balanced at 1440x900, with the official board visible beside their role-specific casebook pages.

### Browser diagnostics

- Chisel console: 0 errors, 0 warnings.
- Detective 1 console: 0 errors, 0 warnings.
- Detective 2 console: 0 errors, 0 warnings.
- No failed game API or WebSocket request was present. Network inspection recorded one aborted top-level Chisel document request when the lobby start navigation was superseded by the successful transition to the same game URL; the game page loaded and remained synchronized.

## Screenshots

- Initial 1440x900 active-Detective board: `output/playwright/cinematic-map-actions/.playwright-cli/page-2026-08-04T08-03-36-789Z.png`
- 390x844 map page: `output/playwright/cinematic-map-actions/.playwright-cli/page-2026-08-04T08-18-20-638Z.png`
- 390x844 casebook bottom sheet and horizontal HUD: `output/playwright/cinematic-map-actions/.playwright-cli/page-2026-08-04T08-18-52-916Z.png`
- Final 1440x900 Detective action desk: `output/playwright/cinematic-map-actions/.playwright-cli/page-2026-08-04T08-19-44-684Z.png`
- Final 1440x900 Chisel private casebook: `output/playwright/cinematic-map-actions/.playwright-cli/page-2026-08-04T08-20-08-937Z.png`

## Automated gate

```text
rtk npm run test:ui
4 files passed, 18 tests passed

rtk mix precommit
client build passed
SSR build passed
277 ExUnit tests passed
```

No scoped implementation defect was found during this acceptance run, so this commit adds QA evidence only.
