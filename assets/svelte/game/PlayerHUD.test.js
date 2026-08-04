import { render, screen, within } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import PlayerHUD from "./PlayerHUD.svelte"

const players = [
  {
    id: "d1",
    role: "detective",
    seat: 1,
    display_name: "Marlowe",
    actions_remaining: 4,
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
  { id: "c1", role: "chisel", display_name: "The Chisel" },
]

const baseProps = {
  players,
  currentDetectiveId: "d1",
  privateState: {},
  onlinePlayerIds: ["d1", "d3", "c1"],
  connectionSnapshotReceived: true,
  disconnectLabel: () => "OFFLINE",
}

describe("PlayerHUD", () => {
  it("renders four Detective slots and never invents Chisel AP or Scratch", () => {
    render(PlayerHUD, {
      ...baseProps,
      privateState: { role: "chisel", leverage_by_detective: { d1: 2 } },
    })

    expect(screen.getAllByTestId(/detective-slot-/)).toHaveLength(4)
    expect(screen.getByTestId("detective-slot-1")).toHaveAttribute("aria-current", "true")
    expect(screen.getByTestId("detective-slot-2")).toHaveTextContent("Open dossier")
    expect(screen.getByTestId("detective-slot-3")).toHaveTextContent("Vega")

    const chisel = screen.getByTestId("chisel-slot")
    expect(chisel).toHaveTextContent("The Chisel")
    expect(chisel).not.toHaveTextContent("AP")
    expect(chisel).not.toHaveTextContent("Scratch")
  })

  it("shows private Detective resources only on their own dossier", () => {
    render(PlayerHUD, {
      ...baseProps,
      privateState: {
        role: "detective",
        player_id: "d1",
        scratch: 6,
        leverage_supply: 2,
        leverage_on_suspects: { suspect: 1 },
      },
    })

    const own = screen.getByTestId("detective-slot-1")
    const other = screen.getByTestId("detective-slot-3")

    expect(own).toHaveTextContent("Scratch 6")
    expect(own).toHaveTextContent("Leverage 3")
    expect(other).not.toHaveTextContent("Scratch")
    expect(other).not.toHaveTextContent("Leverage")
  })

  it("shows Chisel-private leverage and pending response without leaking it to Detectives", async () => {
    const { rerender } = render(PlayerHUD, {
      ...baseProps,
      onlinePlayerIds: ["d1", "c1"],
      privateState: {
        role: "chisel",
        player_id: "c1",
        leverage_by_detective: { d1: 2, d3: 1 },
        pending_interrogation: { id: "pending" },
      },
    })

    const chisel = screen.getByTestId("chisel-slot")
    expect(chisel).toHaveTextContent("Response open")
    expect(chisel).toHaveTextContent("D1 2")
    expect(chisel).toHaveTextContent("D3 1")
    expect(screen.getByTestId("detective-slot-3")).toHaveTextContent("OFFLINE")

    await rerender({
      ...baseProps,
      privateState: { role: "detective", player_id: "d1", scratch: 1 },
    })

    expect(within(screen.getByTestId("chisel-slot")).queryByText(/D1 2/)).not.toBeInTheDocument()
    expect(screen.getByTestId("chisel-slot")).not.toHaveTextContent("Response open")
  })
})
