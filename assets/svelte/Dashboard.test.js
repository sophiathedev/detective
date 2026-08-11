import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"

import Dashboard from "./Dashboard.svelte"

const waiting = {
  id: "g1",
  title: "Midnight Bureau",
  room_code: "ABC234",
  status: "waiting",
  phase: "lobby",
  role: "chisel",
  case_title: "The Pendleton Murders",
  detective_count: 1,
  max_detectives: 4,
  path: "/games/g1/lobby",
}

const finished = {
  ...waiting,
  id: "g2",
  title: "Sealed Ledger",
  status: "finished",
  phase: "finished",
  won: true,
  winner_role: "chisel",
  finish_reason: "time_expired",
  started_at: "2026-08-07T01:00:00Z",
  finished_at: "2026-08-07T02:30:00Z",
  path: "/games/g2",
  replay_path: "/games/g2/replay",
}

const rematchRoom = {
  path: "/games/g3/lobby",
  invite_url: "http://localhost:4000/invites/fresh-token",
  room_code: "REM234",
  duplicate: false,
}

describe("Dashboard", () => {
  it("renders case drawers by server bucket", () => {
    render(Dashboard, {
      display_name: "Mara",
      games: { waiting: 1, active: 0, finished: 0 },
      dossiers: { waiting: [waiting], active: [], finished: [] },
    })

    expect(document.querySelector("#dashboard-case-cabinet.noir-wood-frame")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: /Open Midnight Bureau/i })).toHaveAttribute(
      "href",
      "/games/g1/lobby",
    )
    expect(screen.queryByText("No investigations yet")).not.toBeInTheDocument()
  })

  it("renders a sealed result summary without opening the game snapshot", () => {
    render(Dashboard, {
      display_name: "Mara",
      games: { waiting: 0, active: 0, finished: 1 },
      dossiers: { waiting: [], active: [], finished: [finished] },
    })

    const result = document.querySelector("#dossier-result-g2")
    expect(result).toHaveTextContent("Case closed in your favor")
    expect(result).toHaveTextContent("Trail went cold")
    expect(result).toHaveTextContent("1h 30m")
    expect(document.querySelector("#dossier-rematch-g2")).toHaveAttribute("phx-click", "rematch")
    expect(document.querySelector("#dossier-replay-g2")).toHaveAttribute(
      "href",
      finished.replay_path,
    )
  })

  it("shows the one-time rematch invitation", () => {
    render(Dashboard, {
      display_name: "Mara",
      games: { waiting: 0, active: 0, finished: 1 },
      dossiers: { waiting: [], active: [], finished: [finished] },
      rematch_room: rematchRoom,
    })

    expect(document.querySelector("#rematch-created-title")).toHaveTextContent(
      "Fresh rematch sealed",
    )
    expect(document.querySelector("#rematch-invite-url")).toHaveValue(rematchRoom.invite_url)
    expect(document.querySelector("#enter-rematch")).toHaveAttribute("href", rematchRoom.path)
  })
})
