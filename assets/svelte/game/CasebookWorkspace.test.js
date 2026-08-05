import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"

import CasebookWorkspace from "./CasebookWorkspace.svelte"

const noActions = {
  selectSuspect: () => {},
  selectTopic: () => {},
  setSpendLeverage: () => {},
  submitSuspectSearch: () => {},
  submitLocationSearch: () => {},
  submitInterrogation: () => {},
  allowQuestion: () => {},
  blockQuestion: () => {},
  acceptQuestionBlock: () => {},
  bribeGoon: () => {},
  declineSnitch: () => {},
  chooseSnitch: () => {},
  setBlockedSnitchPlayers: () => {},
  submitSnitchResolution: () => {},
  selectResponse: () => {},
  submitResponse: () => {},
  acceptResponse: () => {},
  challengeResponse: () => {},
  setAccusationSuspect: () => {},
  setAccusationWeapon: () => {},
  setAccusationMotive: () => {},
  submitAccusation: () => {},
  retryCommand: () => {},
}

const baseView = {
  role: "detective",
  phase: "detective_turn",
  result: null,
  activeDetective: { id: "d1", display_name: "Marlowe" },
  ownPlayer: { id: "d1", actions_remaining: 3 },
  availableActions: ["interrogate"],
  search: {
    currentLocation: { id: "48", name: "Bradbury Building" },
    suspects: [],
    selectedSuspectId: null,
    searchableSuspectIds: [],
    interrogatableSuspectIds: [],
  },
  question: {
    pendingPublic: null,
    pendingPrivate: null,
    latestStatement: null,
    interrogationOptions: [],
    selectedSuspectId: null,
    selectedTopicId: null,
    selectedSuspectLeverage: 0,
    spendLeverage: false,
    selectedResponseId: null,
    blockedSnitchPlayerIds: [],
  },
  evidence: { heldEvidence: [], knownCaseCards: [], searchNotes: [] },
  accusation: {
    options: { suspects: [], weapons: [], motives: [] },
    selectedSuspectId: null,
    selectedWeaponId: null,
    selectedMotiveId: null,
    solveAttempt: null,
    finalGuess: null,
  },
  history: {
    entries: [{ type: "case_opened", actorName: "Case file" }],
    lastEvent: "Case opened",
    commandError: null,
    commandStatus: false,
    retryAvailable: false,
  },
  chisel: null,
}

describe("CasebookWorkspace", () => {
  it("requires confirmation before searching the current location", async () => {
    const submitLocationSearch = vi.fn()
    const view = {
      ...baseView,
      availableActions: ["search_location"],
    }

    render(CasebookWorkspace, {
      page: "search",
      view,
      actions: { ...noActions, submitLocationSearch },
    })

    const button = document.querySelector("#casebook-submit-location-search")
    expect(button).toHaveTextContent("Search Bradbury Building")
    expect(button).toBeEnabled()

    await fireEvent.click(button)
    expect(submitLocationSearch).toHaveBeenCalledOnce()
  })

  it("files every private Search note in newest-first order", () => {
    const view = {
      ...baseView,
      evidence: {
        heldEvidence: [],
        knownCaseCards: [],
        searchNotes: [
          { id: "note-2", day: 2, target_type: "suspect", text: "Second filed result." },
          { id: "note-1", day: 1, target_type: "location", text: "First filed result." },
        ],
      },
    }

    render(CasebookWorkspace, { page: "evidence", view, actions: noActions })

    const notes = document.querySelectorAll("#search-note-ledger [data-search-note]")
    expect(notes).toHaveLength(2)
    expect(notes[0]).toHaveTextContent("Second filed result.")
    expect(notes[1]).toHaveTextContent("First filed result.")
  })

  it("routes the selected public history page", () => {
    render(CasebookWorkspace, { page: "history", view: baseView, actions: noActions })

    expect(document.querySelector("#public-case-history")).toHaveTextContent("case opened")
  })

  it("does not render Chisel data in a Detective view", () => {
    render(CasebookWorkspace, { page: "chisel", view: baseView, actions: noActions })

    expect(document.querySelector("#chisel-casebook-page")).not.toBeInTheDocument()
    expect(screen.queryByText(/most useful/i)).not.toBeInTheDocument()
  })

  it("renders the private case only through an explicit Chisel projection", () => {
    const chiselView = {
      ...baseView,
      role: "chisel",
      chisel: {
        identity: { display_name: "The Chisel" },
        pendingInterrogation: null,
        selectedResponseId: null,
        casebook: { briefing: "Private briefing", solution: { suspect_id: "s1" } },
        leverageByDetective: { d1: 2 },
      },
    }

    render(CasebookWorkspace, { page: "chisel", view: chiselView, actions: noActions })

    expect(document.querySelector("#chisel-casebook-page")).toHaveTextContent("Private briefing")
    expect(document.querySelector("#chisel-casebook-page")).toHaveTextContent("s1")
  })
})
