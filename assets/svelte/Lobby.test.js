import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"

import Lobby from "./Lobby.svelte"

const lobby = {
  id: "g1",
  title: "Midnight Bureau",
  room_code: "ABC234",
  status: "waiting",
  phase: "lobby",
  max_detectives: 4,
  current_version: 0,
  case_title: "The Pendleton Murders",
  case_version: 1,
  membership: { id: "p1", role: "chisel", ready: false },
  players: [
    {
      id: "p1",
      display_name: "Elizabeth",
      role: "chisel",
      ready: false,
      seat: null,
    },
  ],
}

describe("Lobby", () => {
  it("renders one Chisel tray and four Detective seats", () => {
    render(Lobby, { lobby })

    expect(screen.getByTestId("lobby-chisel-seat")).toHaveTextContent("Elizabeth")
    expect(screen.getAllByTestId(/lobby-detective-seat-/)).toHaveLength(4)
    expect(screen.getByTestId("lobby-detective-seat-1")).toHaveTextContent("Open seat")
  })

  it("keeps host start disabled without a ready Detective", () => {
    render(Lobby, { lobby })

    expect(screen.getByRole("button", { name: "Waiting for Detectives" })).toBeDisabled()
  })

  it("keeps Classic mode locked with only one ready Detective", () => {
    render(Lobby, {
      lobby: {
        ...lobby,
        players: [
          ...lobby.players,
          {
            id: "p2",
            display_name: "Cal Rowan",
            role: "detective",
            ready: true,
            seat: 1,
          },
        ],
      },
    })

    expect(screen.getByRole("button", { name: "Waiting for Detectives" })).toBeDisabled()
  })
})
