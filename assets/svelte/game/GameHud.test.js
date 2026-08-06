import { render, screen, within } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"

import ChiselConsole from "./ChiselConsole.svelte"
import DetectiveRail from "./DetectiveRail.svelte"

const players = [
  {
    id: "d1",
    role: "detective",
    seat: 1,
    display_name: "Marlowe",
    actions_remaining: 3,
    location_id: "51",
  },
  {
    id: "d3",
    role: "detective",
    seat: 3,
    display_name: "Vega",
    actions_remaining: 2,
    location_id: "84",
  },
]

describe("game HUD role boundaries", () => {
  it("renders four fixed Detective slots and only the current Detective private resources", () => {
    render(DetectiveRail, {
      players,
      currentDetectiveId: "d1",
      ownPlayerId: "d1",
      privateResources: { scratch: 6, leverage: 3 },
      locations: [
        { id: "51", name: "LAPD Headquarters" },
        { id: "84", name: "Bradbury Building" },
      ],
      onlinePlayerIds: ["d1"],
      connectionSnapshotReceived: true,
      disconnectLabel: () => "OFFLINE",
    })

    expect(screen.getAllByTestId(/detective-rail-slot-/)).toHaveLength(4)
    expect(screen.getByLabelText("3 of 4 actions remaining")).toBeInTheDocument()
    const firstSlot = screen.getByTestId("detective-rail-slot-1")
    const thirdSlot = screen.getByTestId("detective-rail-slot-3")

    expect(firstSlot).toHaveAttribute("data-seat", "1")
    expect(firstSlot).toHaveAttribute("data-occupied", "true")
    expect(screen.getByTestId("detective-rail-slot-2")).toHaveAttribute(
      "data-occupied",
      "false",
    )
    expect(within(firstSlot).getByLabelText("Scratch: 6")).toBeInTheDocument()
    expect(within(firstSlot).getByLabelText("Leverage: 3")).toBeInTheDocument()
    expect(firstSlot).toHaveTextContent(
      "At LAPD Headquarters",
    )
    expect(firstSlot).not.toHaveTextContent("LOC 51")
    expect(within(thirdSlot).queryByLabelText(/Scratch:/)).not.toBeInTheDocument()
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
    expect(consoleElement).toHaveTextContent("Question waiting")
    expect(consoleElement).toHaveTextContent("Leverage markers")
    expect(
      within(consoleElement).getByLabelText("2 leverage held for Detective 1"),
    ).toBeInTheDocument()
    expect(within(consoleElement).queryByText(/AP/)).not.toBeInTheDocument()
    expect(within(consoleElement).queryByText(/Scratch/)).not.toBeInTheDocument()
  })

  it("keeps Chisel-private rows sealed for Detective clients", () => {
    render(ChiselConsole, {
      chisel: { id: "c1", display_name: "The Chisel" },
      isCurrentChisel: false,
      pendingInterrogation: { id: "pending" },
      leverageByDetective: { d1: 9 },
      detectiveSlots: players,
      online: true,
      connectionLabel: "ONLINE",
    })

    const consoleElement = screen.getByTestId("chisel-console")
    expect(consoleElement).toHaveTextContent("Chisel notes remain private")
    expect(consoleElement).not.toHaveTextContent("Question waiting")
    expect(consoleElement).not.toHaveTextContent("D1 9 held")
  })
})
