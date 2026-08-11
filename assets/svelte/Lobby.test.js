import { fireEvent, render, screen } from "@testing-library/svelte"
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
  case_version_id: "case-v1",
  case_version: 1,
  invite: {
    status: "active",
    expires_at: "2026-08-07T12:00:00Z",
    uses_remaining: 4,
  },
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

  it("gives the Chisel a sealed invitation desk without exposing a raw token", () => {
    render(Lobby, { lobby })

    expect(screen.getByRole("heading", { name: "Invitation orders" })).toBeInTheDocument()
    expect(screen.getByText("invite active")).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Replace" })).toBeDisabled()
    expect(screen.queryByLabelText("One-time dispatch copy")).not.toBeInTheDocument()
  })

  it("requires a second Chisel action before removing a Detective", async () => {
    render(Lobby, {
      lobby: {
        ...lobby,
        players: [
          ...lobby.players,
          {
            id: "p2",
            display_name: "Cal Rowan",
            role: "detective",
            ready: false,
            seat: 1,
          },
        ],
      },
    })

    await fireEvent.click(screen.getByRole("button", { name: "Remove" }))
    expect(screen.getByRole("button", { name: "Confirm removal" })).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Keep seated" })).toBeInTheDocument()
  })

  it("requires a second Detective action before leaving the room", async () => {
    render(Lobby, {
      lobby: {
        ...lobby,
        membership: { id: "p2", role: "detective", ready: false },
        players: [
          ...lobby.players,
          {
            id: "p2",
            display_name: "Cal Rowan",
            role: "detective",
            ready: false,
            seat: 1,
          },
        ],
      },
    })

    await fireEvent.click(screen.getByRole("button", { name: "Leave investigation room" }))
    expect(screen.getByRole("button", { name: "Confirm exit" })).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Stay in room" })).toBeInTheDocument()
  })

  it("requires a second Chisel action before cancelling the waiting room", async () => {
    render(Lobby, { lobby })

    await fireEvent.click(screen.getByRole("button", { name: "Cancel waiting room" }))
    expect(screen.getByRole("button", { name: "Seal cancellation" })).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Keep room" })).toBeInTheDocument()
  })

  it("opens the Chisel room orders with published case and capacity controls", async () => {
    render(Lobby, {
      lobby,
      case_options: [
        { value: "case-v1", label: "The Pendleton Murders (version 1)" },
        { value: "case-v2", label: "Bloody Christmas (version 1)" },
      ],
    })

    await fireEvent.click(screen.getByRole("button", { name: "Room orders" }))
    expect(screen.getByLabelText("Assigned case file")).toHaveValue("case-v1")
    expect(screen.getByRole("combobox", { name: "Detective seats" })).toHaveValue("4")
    expect(screen.getByRole("button", { name: "Seal changes" })).toBeDisabled()
  })
})
