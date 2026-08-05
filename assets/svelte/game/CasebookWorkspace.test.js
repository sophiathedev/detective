import { fireEvent, render, screen, waitFor } from "@testing-library/svelte"
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
  setBribeMode: () => {},
  setBribeTarget: () => {},
  setBribeCard: () => {},
  submitBribe: () => {},
  setAccusationSuspect: () => {},
  setAccusationWeapon: () => {},
  setAccusationMotive: () => {},
  selectEvidenceCaseCard: () => {},
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
    freeQuestionSuspectId: null,
    selectedSuspectLeverage: 0,
    spendLeverage: false,
    selectedResponseId: null,
    blockedSnitchPlayerIds: [],
  },
  evidence: {
    heldEvidence: [],
    knownCaseCards: [],
    caseCards: [],
    selectedCaseCardCode: null,
    searchNotes: [],
  },
  bribes: {
    mode: "detective",
    scratch: 4,
    options: { detective_targets: [], officer_case_cards: [] },
    selectedTargetId: null,
    selectedCardId: null,
  },
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
  it("selects an interrogation subject directly from the Question folio", async () => {
    const selectSuspect = vi.fn()
    const view = {
      ...baseView,
      question: {
        ...baseView.question,
        interrogationOptions: [
          {
            suspect_id: "iona-pike",
            suspect_name: "Iona Pike",
            topics: [{ id: "signal-log", code: "C", title: "Altered Signal Log" }],
          },
        ],
      },
    }

    render(CasebookWorkspace, {
      page: "question",
      view,
      actions: { ...noActions, selectSuspect },
    })

    const subject = document.querySelector("#casebook-question-suspect-iona-pike")
    expect(subject).toHaveTextContent("Iona Pike")

    await fireEvent.click(subject)
    expect(selectSuspect).toHaveBeenCalledWith("iona-pike")
  })

  it("marks an immediate discovered-suspect question as free", () => {
    const interrogation = {
      suspect_id: "iona-pike",
      suspect_name: "Iona Pike",
      topics: [{ id: "signal-log", code: "C", title: "Altered Signal Log" }],
    }
    const view = {
      ...baseView,
      question: {
        ...baseView.question,
        interrogationOptions: [interrogation],
        selectedSuspectId: "iona-pike",
        selectedTopicId: "signal-log",
        freeQuestionSuspectId: "iona-pike",
      },
    }

    render(CasebookWorkspace, { page: "question", view, actions: noActions })

    expect(document.querySelector("#casebook-submit-interrogation")).toHaveTextContent("FREE")
  })

  it("requires a sealed confirmation before spending a Solve token", async () => {
    const submitAccusation = vi.fn()
    const view = {
      ...baseView,
      availableActions: ["accuse"],
      accusation: {
        ...baseView.accusation,
        options: {
          suspects: [{ id: "iona-pike", name: "Iona Pike" }],
          weapons: [{ id: "wire", label: "Piano Wire" }],
          motives: [{ id: "blackmail", label: "Blackmail" }],
        },
        selectedSuspectId: "iona-pike",
        selectedWeaponId: "wire",
        selectedMotiveId: "blackmail",
      },
    }

    render(CasebookWorkspace, {
      page: "accusation",
      view,
      actions: { ...noActions, submitAccusation },
    })

    await fireEvent.click(document.querySelector("#casebook-submit-accusation"))
    expect(submitAccusation).not.toHaveBeenCalled()
    expect(document.querySelector("#accusation-confirmation")).toHaveTextContent(
      "Iona Pike",
    )

    await fireEvent.click(document.querySelector("#casebook-confirm-accusation"))
    expect(submitAccusation).toHaveBeenCalledOnce()
  })

  it("keeps bribed Case content sealed until payment is confirmed", async () => {
    const submitBribe = vi.fn()
    const view = {
      ...baseView,
      availableActions: ["bribe_detective"],
      bribes: {
        mode: "detective",
        scratch: 4,
        options: {
          detective_targets: [
            {
              player_id: "d2",
              display_name: "Rowan",
              case_cards: [{ id: "sealed-ledger", code: "B" }],
            },
          ],
          officer_case_cards: [],
        },
        selectedTargetId: "d2",
        selectedCardId: "sealed-ledger",
      },
    }

    render(CasebookWorkspace, {
      page: "bribes",
      view,
      actions: { ...noActions, submitBribe },
    })

    expect(document.querySelector("#bribe-case-card-sealed-ledger")).toHaveTextContent(
      "Case B",
    )
    expect(document.querySelector("#bribe-folio")).not.toHaveTextContent("Sealed Ledger")

    await fireEvent.click(document.querySelector("#casebook-submit-bribe"))
    expect(submitBribe).not.toHaveBeenCalled()

    await fireEvent.click(document.querySelector("#casebook-confirm-bribe"))
    expect(submitBribe).toHaveBeenCalledOnce()
  })

  it("shows public final-guess filing progress without revealing choices", () => {
    const view = {
      ...baseView,
      phase: "accusation",
      availableActions: ["submit_final_guess"],
      detectives: [
        { id: "d1", display_name: "Marlowe", final_guess_submitted: true },
        { id: "d2", display_name: "Rowan", final_guess_submitted: false },
      ],
      accusation: {
        ...baseView.accusation,
        options: {
          suspects: [{ id: "iona-pike", name: "Iona Pike" }],
          weapons: [{ id: "wire", label: "Piano Wire" }],
          motives: [{ id: "blackmail", label: "Blackmail" }],
        },
      },
    }

    render(CasebookWorkspace, { page: "accusation", view, actions: noActions })

    expect(document.querySelector("#final-guess-progress")).toHaveTextContent("1 / 2 filed")
    expect(document.querySelector("#final-guess-player-d1")).toHaveTextContent("FILED")
    expect(document.querySelector("#final-guess-player-d2")).toHaveTextContent("PENDING")
  })

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
        caseCards: [],
        selectedCaseCardCode: null,
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

  it("indexes only accessible Case cards and brings the selected card into view", async () => {
    const scrollIntoView = vi.fn()
    const selectEvidenceCaseCard = vi.fn()
    Element.prototype.scrollIntoView = scrollIntoView
    const view = {
      ...baseView,
      evidence: {
        ...baseView.evidence,
        caseCards: [
          {
            id: "victim-file",
            code: "A",
            title: "Victim File",
            description: "Public victim details.",
            visibility: "public",
          },
          {
            id: "copper-key",
            code: "B",
            title: "Copper Tuning Key",
            description: "A detail known only to this Detective.",
            visibility: "known",
          },
        ],
        selectedCaseCardCode: "B",
      },
    }

    render(CasebookWorkspace, {
      page: "evidence",
      view,
      actions: { ...noActions, selectEvidenceCaseCard },
    })

    expect(document.querySelector("#evidence-case-card-A")).toHaveTextContent("Victim File")
    expect(document.querySelector("#evidence-case-card-B")).toHaveAttribute(
      "aria-current",
      "true",
    )
    expect(document.querySelector("#evidence-case-card-B")).toHaveTextContent(
      "Copper Tuning Key",
    )
    expect(screen.queryByText("Sealed Case C")).not.toBeInTheDocument()
    await waitFor(() => expect(scrollIntoView).toHaveBeenCalledWith({ block: "nearest" }))

    await fireEvent.click(document.querySelector("#evidence-case-card-A"))
    expect(selectEvidenceCaseCard).toHaveBeenCalledWith("A")
  })

  it("links only projected Search and held-evidence references to board cards", async () => {
    const selectEvidenceCaseCard = vi.fn()
    const card = {
      id: "copper-key",
      code: "B",
      title: "Copper Tuning Key",
      description: "A private evidence detail.",
      visibility: "held",
    }
    const view = {
      ...baseView,
      evidence: {
        ...baseView.evidence,
        heldEvidence: [card],
        knownCaseCards: [card],
        caseCards: [card],
        searchNotes: [
          {
            day: 1,
            target_type: "location",
            text: "A tuning key was recovered.",
            case_card_ids: ["copper-key", "sealed-case-c"],
            taken_case_card_ids: ["copper-key"],
          },
        ],
      },
    }

    render(CasebookWorkspace, {
      page: "evidence",
      view,
      actions: { ...noActions, selectEvidenceCaseCard },
    })

    const revealed = document.querySelector("#search-note-revealed-0-copper-key")
    const held = document.querySelector("#held-evidence-copper-key")

    expect(revealed).toHaveTextContent("Case B")
    expect(document.querySelector('[data-inert-case-card="sealed-case-c"]')).toHaveTextContent(
      "sealed-case-c",
    )
    expect(document.querySelector("#search-note-revealed-0-sealed-case-c")).not.toBeInTheDocument()

    await fireEvent.click(revealed)
    await fireEvent.click(held)
    expect(selectEvidenceCaseCard).toHaveBeenNthCalledWith(1, "B")
    expect(selectEvidenceCaseCard).toHaveBeenNthCalledWith(2, "B")
  })

  it("routes the selected public history page", () => {
    render(CasebookWorkspace, { page: "history", view: baseView, actions: noActions })

    expect(document.querySelector("#public-case-history")).toHaveTextContent("case opened")
  })

  it("renders public special rules as casebook directives", () => {
    const view = {
      ...baseView,
      specialRules: [
        {
          id: "short-clock",
          title: "Short Clock",
          text: "Use the shortened Day track.",
          trigger: "setup",
          triggered: false,
        },
      ],
    }

    render(CasebookWorkspace, { page: "history", view, actions: noActions })

    expect(document.querySelector("#case-special-rule-short-clock")).toHaveTextContent(
      "Use the shortened Day track.",
    )
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
        casebook: {
          briefing: "Private briefing",
          solution: { suspect_id: "s1" },
          special_rules: [
            {
              id: "hidden-arrival",
              title: "Hidden Arrival",
              text: "Reveal a witness on Day 2.",
            },
          ],
        },
        leverageByDetective: { d1: 2 },
      },
    }

    render(CasebookWorkspace, { page: "chisel", view: chiselView, actions: noActions })

    expect(document.querySelector("#chisel-casebook-page")).toHaveTextContent("Private briefing")
    expect(document.querySelector("#chisel-casebook-page")).toHaveTextContent("s1")
    expect(document.querySelector("#chisel-special-rule-hidden-arrival")).toHaveTextContent(
      "Reveal a witness on Day 2.",
    )
  })
})
