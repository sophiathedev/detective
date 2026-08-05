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
  actionableDetectiveId: null,
  detectiveActionTypes: [],
  selectedDetectiveId: null,
  detectiveInteractionsDisabled: false,
  suspects: [],
  searchableSuspectIds: [],
  interrogatableSuspectIds: [],
  selectedSuspectId: null,
  suspectInteractionsDisabled: false,
  inspectableCaseCardCodes: [],
  selectedCaseCardCode: null,
  legalLocationIds: [],
  selectedLocationId: null,
  pendingLocationId: null,
  lastTravel: null,
  disabled: false,
  status: "Observing",
  onSelect: vi.fn(),
  onSelectDetective: vi.fn(),
  onSelectSuspect: vi.fn(),
  onSelectCaseCard: vi.fn(),
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

  it("forwards authorized suspect interaction to the board", async () => {
    const onSelectSuspect = vi.fn()
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
      searchableSuspectIds: ["iona-pike"],
      selectedSuspectId: "iona-pike",
      onSelectSuspect,
    })

    const standee = screen.getByTestId("suspect-standee-iona-pike")
    expect(standee).toHaveAttribute("aria-pressed", "true")
    await fireEvent.click(standee)
    expect(onSelectSuspect).toHaveBeenCalledWith(expect.objectContaining({ id: "iona-pike" }))
  })

  it("forwards authorized field actions to the own Detective token", async () => {
    const detective = {
      id: "detective-1",
      role: "detective",
      seat: 1,
      display_name: "Marlowe",
      location_id: "51",
    }
    const onSelectDetective = vi.fn()

    render(MapStage, {
      ...baseProps,
      detectives: [detective],
      actionableDetectiveId: detective.id,
      detectiveActionTypes: ["analyze"],
      selectedDetectiveId: detective.id,
      onSelectDetective,
    })

    const token = screen.getByTestId("detective-token-detective-1")
    expect(token).toHaveAttribute("aria-pressed", "true")
    await fireEvent.click(token)
    expect(onSelectDetective).toHaveBeenCalledWith(detective)
  })

  it("forwards projected Case-card inspection to the board", async () => {
    const onSelectCaseCard = vi.fn()
    const slot = {
      code: "A",
      position: 1,
      status: "faceup",
      type: "victim",
      title: "Victim File",
      knowledge_player_ids: [],
      evidence_holder_player_id: null,
      evidence_release_day: null,
    }

    render(MapStage, {
      ...baseProps,
      caseCardSlots: [slot],
      inspectableCaseCardCodes: ["A"],
      onSelectCaseCard,
    })

    await fireEvent.click(screen.getByTestId("case-card-action-A"))
    expect(onSelectCaseCard).toHaveBeenCalledWith(slot)
  })

  it("zooms inside the contained map viewport", async () => {
    render(MapStage, baseProps)

    await fireEvent.click(screen.getByRole("button", { name: "Zoom in" }))
    expect(document.querySelector("#map-zoom-plane")).toHaveAttribute("data-zoom", "1.25")

    await fireEvent.click(screen.getByRole("button", { name: "Reset map zoom" }))
    expect(document.querySelector("#map-zoom-plane")).toHaveAttribute("data-zoom", "1")
  })
})
