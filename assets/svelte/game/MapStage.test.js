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

const baseProps = {
  locations: [location],
  detectives: [],
  suspects: [],
  legalLocationIds: [],
  selectedLocationId: null,
  pendingLocationId: null,
  lastTravel: null,
  disabled: false,
  status: "Observing",
  onSelect: vi.fn(),
}

describe("MapStage", () => {
  it("forwards only enabled legal destination intent", async () => {
    const onSelect = vi.fn()
    const { rerender } = render(MapStage, {
      ...baseProps,
      legalLocationIds: ["51"],
      disabled: true,
      status: "Choose Move",
      onSelect,
    })

    await fireEvent.click(screen.getByTestId("map-hotspot-51"))
    expect(onSelect).not.toHaveBeenCalled()

    await rerender({
      ...baseProps,
      legalLocationIds: ["51"],
      status: "Choose destination",
      onSelect,
    })
    await fireEvent.click(screen.getByTestId("map-hotspot-51"))
    expect(onSelect).toHaveBeenCalledWith(location)
  })

  it("keeps board attribution visible", () => {
    render(MapStage, baseProps)

    expect(screen.getByText(/Van Ryder Games/)).toBeInTheDocument()
  })

  it("forwards public suspects to the board", () => {
    render(MapStage, {
      ...baseProps,
      suspects: [
        {
          id: "iona-pike",
          name: "Iona Pike",
          occupation: "array engineer",
          location_id: "51",
        },
      ],
    })

    expect(screen.getByTestId("suspect-standee-iona-pike")).toBeInTheDocument()
  })

  it("zooms inside the contained map viewport", async () => {
    render(MapStage, baseProps)

    await fireEvent.click(screen.getByRole("button", { name: "Zoom in" }))
    expect(document.querySelector("#map-zoom-plane")).toHaveAttribute("data-zoom", "1.25")

    await fireEvent.click(screen.getByRole("button", { name: "Reset map zoom" }))
    expect(document.querySelector("#map-zoom-plane")).toHaveAttribute("data-zoom", "1")
  })
})
