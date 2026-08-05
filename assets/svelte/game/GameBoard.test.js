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
  actionableDetectiveId: null,
  detectiveActionTypes: [],
  selectedDetectiveId: null,
  detectiveInteractionsDisabled: false,
  suspects: [],
  searchableSuspectIds: [],
  interrogatableSuspectIds: [],
  selectedSuspectId: null,
  suspectInteractionsDisabled: false,
  specialActors: [],
  interactableSpecialActorIds: [],
  selectedSpecialActorId: null,
  specialActorInteractionsDisabled: false,
  inspectableCaseCardCodes: [],
  selectedCaseCardCode: null,
  legalLocationIds: ["51"],
  selectedLocationId: null,
  pendingLocationId: null,
  lastTravel: null,
  disabled: false,
  onSelectDetective: vi.fn(),
  onSelectSuspect: vi.fn(),
  onSelectSpecialActor: vi.fn(),
  onSelectCaseCard: vi.fn(),
}

describe("GameBoard", () => {
  it("selects only legal pointer and keyboard destinations", async () => {
    const onSelect = vi.fn()
    render(GameBoard, { ...baseProps, onSelect })

    const legal = screen.getByTestId("map-hotspot-51")
    const illegal = screen.getByTestId("map-hotspot-48")

    expect(legal).toHaveAttribute("role", "button")
    expect(legal).toHaveAttribute("tabindex", "0")
    expect(legal).toHaveAttribute("focusable", "true")
    expect(illegal).not.toHaveAttribute("role")
    expect(illegal).not.toHaveAttribute("tabindex")
    expect(illegal).toHaveAttribute("focusable", "false")

    await fireEvent.click(illegal)
    await fireEvent.keyDown(illegal, { key: "Enter" })
    expect(onSelect).not.toHaveBeenCalled()

    await fireEvent.keyDown(legal, { key: "Escape" })
    expect(onSelect).not.toHaveBeenCalled()

    await fireEvent.keyDown(legal, { key: "Enter" })
    await fireEvent.keyDown(legal, { key: " " })
    await fireEvent.click(
      screen.getByRole("button", {
        name: /^Choose L\.A\. Police Department Headquarters$/i,
      }),
    )

    expect(onSelect).toHaveBeenNthCalledWith(1, locations[1])
    expect(onSelect).toHaveBeenNthCalledWith(2, locations[1])
    expect(onSelect).toHaveBeenNthCalledWith(3, locations[1])
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
    expect(screen.queryByRole("button", { name: /Bradbury Building/i })).not.toBeInTheDocument()

    await fireEvent.click(hotspot)
    expect(onSelect).not.toHaveBeenCalled()
  })

  it("keeps fallback destination buttons in parity with legal SVG hotspots", () => {
    render(GameBoard, {
      ...baseProps,
      legalLocationIds: ["48", "51"],
      onSelect: vi.fn(),
    })

    const legalHotspots = locations.filter((location) =>
      screen.getByTestId(`map-hotspot-${location.id}`).hasAttribute("role"),
    )
    const fallbackButtons = screen.getAllByRole("button", { name: /^Choose /i })

    expect(fallbackButtons).toHaveLength(legalHotspots.length)
    expect(fallbackButtons.map((button) => button.textContent.trim())).toEqual([
      "Choose Bradbury Building",
      "Choose L.A. Police Department Headquarters",
    ])
    expect(fallbackButtons.map((button) => button.dataset.locationId)).toEqual(["48", "51"])
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

  it("mounts Case cards and knowledge markers on the board plane", () => {
    render(GameBoard, {
      ...baseProps,
      detectives: [
        {
          id: "detective-1",
          role: "detective",
          seat: 1,
          display_name: "Marlowe",
          location_id: null,
        },
      ],
      caseCardSlots: [
        {
          code: "B",
          position: 2,
          status: "facedown",
          knowledge_player_ids: ["detective-1"],
          evidence_holder_player_id: null,
          evidence_release_day: null,
        },
      ],
      onSelect: vi.fn(),
    })

    expect(screen.getByTestId("case-card-slot-B")).toHaveAccessibleName(
      "Case B facedown. Known by D1 Marlowe.",
    )
    expect(screen.getByTestId("case-card-slot-B")).toContainElement(
      document.querySelector('.noir-case-knowledge-marker[data-seat="1"]'),
    )
  })

  it("forwards projected Case-card inspection from the board rail", async () => {
    const onSelectCaseCard = vi.fn()
    const slot = {
      code: "B",
      position: 2,
      status: "facedown",
      knowledge_player_ids: ["detective-1"],
      evidence_holder_player_id: null,
      evidence_release_day: null,
    }

    render(GameBoard, {
      ...baseProps,
      detectives: [
        {
          id: "detective-1",
          role: "detective",
          seat: 1,
          display_name: "Marlowe",
          location_id: null,
        },
      ],
      caseCardSlots: [slot],
      inspectableCaseCardCodes: ["B"],
      selectedCaseCardCode: "B",
      onSelectCaseCard,
    })

    const action = screen.getByTestId("case-card-action-B")
    expect(action).toHaveAttribute("aria-pressed", "true")
    await fireEvent.click(action)
    expect(onSelectCaseCard).toHaveBeenCalledWith(slot)
  })

  it("activates only the authorized Detective token as a field-action hub", async () => {
    const onSelectDetective = vi.fn()
    const detectives = [
      {
        id: "detective-1",
        role: "detective",
        seat: 1,
        display_name: "Marlowe",
        location_id: "51",
      },
      {
        id: "detective-2",
        role: "detective",
        seat: 2,
        display_name: "Archer",
        location_id: "51",
      },
    ]
    const { rerender } = render(GameBoard, {
      ...baseProps,
      detectives,
      actionableDetectiveId: "detective-1",
      detectiveActionTypes: ["search_location", "analyze"],
      selectedDetectiveId: "detective-1",
      onSelectDetective,
    })

    const ownToken = screen.getByTestId("detective-token-detective-1")
    const otherToken = screen.getByTestId("detective-token-detective-2")

    expect(ownToken).toHaveAccessibleName(
      "Marlowe at L.A. Police Department Headquarters. Available actions: search location, analyze evidence.",
    )
    expect(ownToken).toHaveAttribute("role", "button")
    expect(ownToken).toHaveAttribute("tabindex", "0")
    expect(ownToken).toHaveAttribute("aria-pressed", "true")
    expect(otherToken).toHaveAttribute("role", "img")
    expect(otherToken).toHaveAttribute("data-actionable", "false")

    await fireEvent.keyDown(ownToken, { key: "Escape" })
    expect(onSelectDetective).not.toHaveBeenCalled()
    await fireEvent.keyDown(ownToken, { key: " " })
    await fireEvent.click(ownToken)
    expect(onSelectDetective).toHaveBeenCalledTimes(2)
    expect(onSelectDetective).toHaveBeenLastCalledWith(
      expect.objectContaining({ id: "detective-1" }),
    )

    await rerender({
      ...baseProps,
      detectives,
      actionableDetectiveId: "detective-1",
      detectiveActionTypes: ["analyze"],
      detectiveInteractionsDisabled: true,
      onSelectDetective,
    })
    expect(screen.getByTestId("detective-token-detective-1")).toHaveAttribute("role", "img")
  })

  it("separates co-located suspects and exposes only authorized standees", async () => {
    const onSelectSuspect = vi.fn()
    render(GameBoard, {
      ...baseProps,
      detectives: [
        {
          id: "detective-1",
          role: "detective",
          seat: 1,
          display_name: "Marlowe",
          location_id: "51",
        },
      ],
      suspects: [
        {
          id: "iona-pike",
          name: "Iona Pike",
          occupation: "array engineer",
          location_id: "51",
        },
        {
          id: "celeste-rook",
          name: "Celeste Rook",
          occupation: "journalist",
          location_id: "51",
        },
        {
          id: "off-board",
          name: "Unknown Caller",
          occupation: "informant",
          location_id: "404",
        },
      ],
      searchableSuspectIds: ["iona-pike"],
      interrogatableSuspectIds: ["iona-pike"],
      selectedSuspectId: "iona-pike",
      onSelectSuspect,
      onSelect: vi.fn(),
    })

    const iona = screen.getByTestId("suspect-standee-iona-pike")
    const celeste = screen.getByTestId("suspect-standee-celeste-rook")

    expect(iona).toHaveAccessibleName(
      "Iona Pike, array engineer, at L.A. Police Department Headquarters. Available actions: search and question.",
    )
    expect(celeste).toHaveAccessibleName(
      "Celeste Rook, journalist, at L.A. Police Department Headquarters",
    )
    expect(iona).toHaveAttribute("data-location-id", "51")
    expect(iona).toHaveAttribute("role", "button")
    expect(iona).toHaveAttribute("tabindex", "0")
    expect(iona).toHaveAttribute("aria-pressed", "true")
    expect(celeste).toHaveAttribute("role", "img")
    expect(celeste).not.toHaveAttribute("tabindex")
    expect(iona).toHaveStyle({ transform: "translate(482px, 360px)" })
    expect(celeste).toHaveStyle({ transform: "translate(502px, 360px)" })
    expect(iona.getAttribute("style")).not.toEqual(celeste.getAttribute("style"))
    expect(screen.queryByTestId("suspect-standee-off-board")).not.toBeInTheDocument()

    await fireEvent.keyDown(iona, { key: "Escape" })
    expect(onSelectSuspect).not.toHaveBeenCalled()

    await fireEvent.keyDown(iona, { key: "Enter" })
    await fireEvent.click(iona)
    expect(onSelectSuspect).toHaveBeenCalledTimes(2)
    expect(onSelectSuspect).toHaveBeenLastCalledWith(
      expect.objectContaining({ id: "iona-pike" }),
    )
  })

  it("seals suspect interaction while another map mode is active", () => {
    render(GameBoard, {
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
      suspectInteractionsDisabled: true,
    })

    const standee = screen.getByTestId("suspect-standee-iona-pike")
    expect(standee).toHaveAttribute("role", "img")
    expect(standee).toHaveAttribute("data-actionable", "false")
  })

  it("renders case-specific actors as graphic map tokens and authorizes only legal interaction", async () => {
    const onSelectSpecialActor = vi.fn()
    const specialActors = [
      {
        id: "station-tail",
        name: "Station Tail",
        role: "counter-surveillance lookout",
        kind: "counter_surveillance",
        location_id: "51",
        active: true,
      },
      {
        id: "retired-contact",
        name: "Retired Contact",
        role: "former informant",
        kind: "contact",
        location_id: "48",
        active: false,
      },
    ]

    const { rerender } = render(GameBoard, {
      ...baseProps,
      specialActors: [],
      interactableSpecialActorIds: ["station-tail"],
      selectedSpecialActorId: "station-tail",
      onSelectSpecialActor,
    })

    expect(screen.queryByTestId("special-actor-station-tail")).not.toBeInTheDocument()

    await rerender({
      ...baseProps,
      specialActors,
      interactableSpecialActorIds: ["station-tail"],
      selectedSpecialActorId: "station-tail",
      onSelectSpecialActor,
    })

    const tail = screen.getByTestId("special-actor-station-tail")
    const retired = screen.getByTestId("special-actor-retired-contact")

    expect(tail).toHaveAttribute("role", "button")
    expect(tail).toHaveAttribute("aria-pressed", "true")
    expect(tail).toHaveAttribute("data-kind", "counter_surveillance")
    expect(tail).toHaveAccessibleName(
      "Station Tail, counter-surveillance lookout, at L.A. Police Department Headquarters. active. Select to review special interactions.",
    )
    expect(retired).toHaveAttribute("role", "img")
    expect(retired).toHaveAttribute("data-active", "false")

    await fireEvent.keyDown(tail, { key: "Enter" })
    await fireEvent.click(tail)
    expect(onSelectSpecialActor).toHaveBeenCalledTimes(2)

    await rerender({
      ...baseProps,
      specialActors,
      interactableSpecialActorIds: ["station-tail"],
      specialActorInteractionsDisabled: true,
      onSelectSpecialActor,
    })

    expect(screen.getByTestId("special-actor-station-tail")).toHaveAttribute("role", "img")
  })
})
