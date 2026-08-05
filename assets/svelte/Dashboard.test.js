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
})
