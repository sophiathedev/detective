import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"

import CaseCardRail from "./CaseCardRail.svelte"

const players = [
  { id: "detective-1", role: "detective", seat: 1, display_name: "Marlowe" },
  { id: "detective-2", role: "detective", seat: 2, display_name: "Archer" },
  { id: "detective-3", role: "detective", seat: 3, display_name: "Vega" },
  { id: "detective-4", role: "detective", seat: 4, display_name: "Ellis" },
]

const slots = [
  {
    code: "A",
    position: 1,
    status: "faceup",
    title: "Victim File",
    type: "victim",
    knowledge_player_ids: [],
    evidence_holder_player_id: null,
    evidence_release_day: null,
  },
  {
    code: "B",
    position: 2,
    status: "facedown",
    knowledge_player_ids: ["detective-1", "detective-3"],
    evidence_holder_player_id: null,
    evidence_release_day: null,
  },
  {
    code: "C",
    position: 3,
    status: "removed",
    knowledge_player_ids: ["detective-2", "detective-4"],
    evidence_holder_player_id: "detective-2",
    evidence_release_day: 4,
  },
]

describe("CaseCardRail", () => {
  it("lays cards over their board spaces and keeps facedown contents sealed", () => {
    render(CaseCardRail, { slots, players })

    expect(screen.getByLabelText("Case cards and public knowledge markers")).toBeInTheDocument()
    expect(screen.getByTestId("case-card-slot-A")).toHaveAttribute("data-status", "faceup")
    expect(screen.getByTestId("case-card-slot-A")).toHaveTextContent("Victim File")
    expect(screen.getByTestId("case-card-slot-B")).toHaveAttribute("data-status", "facedown")
    expect(screen.getByTestId("case-card-slot-B")).not.toHaveTextContent("Hidden Fingerprint")
    expect(screen.getByTestId("case-card-slot-C")).toHaveTextContent("Removed")
    expect(screen.getByTestId("case-card-slot-C")).toHaveTextContent("Day 4")
  })

  it("shows public knowledge markers in each Detective color seat", () => {
    render(CaseCardRail, { slots, players })

    const facedownMarkers = screen
      .getByTestId("case-card-slot-B")
      .querySelectorAll(".noir-case-knowledge-marker")
    const removedMarkers = screen
      .getByTestId("case-card-slot-C")
      .querySelectorAll(".noir-case-knowledge-marker")

    expect([...facedownMarkers].map((marker) => marker.dataset.seat)).toEqual(["1", "3"])
    expect([...removedMarkers].map((marker) => marker.dataset.seat)).toEqual(["2", "4"])
    expect(screen.getByTestId("case-card-slot-B")).toHaveAccessibleName(
      "Case B facedown. Known by D1 Marlowe, D3 Vega.",
    )
    expect(screen.getByTestId("case-card-slot-C")).toHaveAccessibleName(
      "Case C evidence removed by D2 Archer. Returns faceup on Day 4. Known by D2 Archer, D4 Ellis.",
    )
  })
})
