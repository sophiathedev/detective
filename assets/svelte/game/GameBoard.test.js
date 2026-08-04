import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"
import GameBoard from "./GameBoard.svelte"

const locations = [
  {
    id: "48",
    name: "Bradbury Building",
    type: "standard",
    district_ids: ["central_la"],
    x: 0.48,
    y: 0.43,
  },
  {
    id: "51",
    name: "L.A. Police Department Headquarters",
    type: "police_station",
    district_ids: ["central_la"],
    x: 0.52,
    y: 0.5,
  },
]

const baseProps = {
  locations,
  detectives: [],
  legalLocationIds: ["51"],
  selectedLocationId: null,
  pendingLocationId: null,
  lastTravel: null,
  disabled: false,
}

describe("GameBoard", () => {
  it("selects only legal pointer and keyboard destinations", async () => {
    const onSelect = vi.fn()
    render(GameBoard, { ...baseProps, onSelect })

    const legal = screen.getByTestId("map-hotspot-51")
    const illegal = screen.getByTestId("map-hotspot-48")

    expect(legal).toHaveAttribute("role", "button")
    expect(legal).toHaveAttribute("tabindex", "0")
    expect(illegal).not.toHaveAttribute("role")
    expect(illegal).not.toHaveAttribute("tabindex")

    await fireEvent.click(illegal)
    await fireEvent.keyDown(illegal, { key: "Enter" })
    expect(onSelect).not.toHaveBeenCalled()

    await fireEvent.keyDown(legal, { key: "Escape" })
    expect(onSelect).not.toHaveBeenCalled()

    await fireEvent.keyDown(legal, { key: "Enter" })
    await fireEvent.click(
      screen.getByRole("button", {
        name: /^Choose L\.A\. Police Department Headquarters$/i,
      }),
    )

    expect(onSelect).toHaveBeenNthCalledWith(1, locations[1])
    expect(onSelect).toHaveBeenNthCalledWith(2, locations[1])
  })

  it("removes interaction semantics while disabled", async () => {
    const onSelect = vi.fn()
    render(GameBoard, { ...baseProps, disabled: true, onSelect })

    const hotspot = screen.getByTestId("map-hotspot-51")
    expect(hotspot).not.toHaveAttribute("role")
    expect(hotspot).not.toHaveAttribute("tabindex")
    expect(
      screen.queryByRole("button", {
        name: /^Choose L\.A\. Police Department Headquarters$/i,
      }),
    ).not.toBeInTheDocument()

    await fireEvent.click(hotspot)
    expect(onSelect).not.toHaveBeenCalled()
  })

  it("uses the official board plane and marks selected and pending locations", () => {
    render(GameBoard, {
      ...baseProps,
      selectedLocationId: "48",
      pendingLocationId: "51",
      onSelect: vi.fn(),
    })

    expect(screen.getByTestId("game-map")).toHaveAttribute("viewBox", "0 0 1000 636")
    expect(screen.getByTestId("official-board-image")).toHaveAttribute(
      "href",
      "/images/maps/dcoa/game-board-final.png",
    )
    expect(screen.getByTestId("map-hotspot-48")).toHaveAttribute("data-selected", "true")
    expect(screen.getByTestId("map-hotspot-51")).toHaveAttribute("aria-busy", "true")
  })
})
