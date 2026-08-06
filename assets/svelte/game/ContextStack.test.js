import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"

import ContextStack from "./ContextStack.svelte"

const selection = {
  type: "move",
  location: { id: "48", name: "Bradbury Building", district_ids: ["central_la"] },
}

describe("ContextStack", () => {
  it("previews without confirming until the physical control is clicked", async () => {
    const onConfirmMove = vi.fn()
    const onCancelMove = vi.fn()

    render(ContextStack, {
      selection,
      origin: { id: "51", name: "LAPD Headquarters" },
      commandPending: false,
      commandError: null,
      commandStatus: false,
      connectionOnline: true,
      onConfirmMove,
      onCancelMove,
    })

    expect(onConfirmMove).not.toHaveBeenCalled()
    expect(screen.getByText("Bradbury Building")).toBeInTheDocument()
    expect(document.querySelector("#movement-slip")).toHaveTextContent("Movement cost · 1 AP")
    await fireEvent.click(screen.getByRole("button", { name: "Confirm Move" }))
    await fireEvent.click(screen.getByRole("button", { name: "Cancel Move" }))
    expect(onConfirmMove).toHaveBeenCalledWith(selection)
    expect(onCancelMove).toHaveBeenCalledWith(selection)
  })

  it("announces stale sync as status rather than an alert", () => {
    render(ContextStack, {
      selection: null,
      origin: null,
      commandPending: false,
      commandError: "Game state changed; map resynchronized",
      commandStatus: true,
      connectionOnline: true,
      onConfirmMove: vi.fn(),
      onCancelMove: vi.fn(),
    })

    expect(screen.getByRole("status")).toHaveTextContent("map resynchronized")
    expect(screen.queryByRole("alert")).not.toBeInTheDocument()
  })

  it("holds an immediate field action until the dispatch slip is confirmed", async () => {
    const prompt = {
      type: "kickback",
      stamp: "KICKBACK",
      kicker: "Mob Joint collection",
      title: "Collect $3 Scratch",
      description: "Costs 1 action and can be used only once this Day.",
      confirmLabel: "Collect kickback",
    }
    const onConfirmAction = vi.fn()

    render(ContextStack, {
      selection: null,
      actionPrompt: prompt,
      origin: { id: "22", name: "The Stag & Bull" },
      commandPending: false,
      commandError: null,
      commandStatus: false,
      connectionOnline: true,
      onConfirmAction,
      onCancelAction: vi.fn(),
    })

    expect(onConfirmAction).not.toHaveBeenCalled()
    expect(document.querySelector("#action-confirmation-slip")).toHaveTextContent(
      "Collect $3 Scratch",
    )

    await fireEvent.click(screen.getByRole("button", { name: "Collect kickback" }))
    expect(onConfirmAction).toHaveBeenCalledWith(prompt)
  })

  it("opens only the server-authorized folios from a suspect slip", async () => {
    const suspectSelection = {
      suspect: { id: "iona-pike", name: "Iona Pike", occupation: "array engineer" },
      location: { id: "51", name: "LAPD Headquarters" },
      canSearch: true,
      canInterrogate: true,
    }
    const onOpenSuspectAction = vi.fn()
    const onCancelSuspect = vi.fn()

    render(ContextStack, {
      selection: null,
      suspectSelection,
      commandPending: false,
      commandError: null,
      commandStatus: false,
      connectionOnline: true,
      onOpenSuspectAction,
      onCancelSuspect,
    })

    expect(document.querySelector("#suspect-dossier-slip")).toHaveTextContent(
      "Iona Pike",
    )
    expect(onOpenSuspectAction).not.toHaveBeenCalled()

    await fireEvent.click(screen.getByRole("button", { name: "Open Search" }))
    await fireEvent.click(screen.getByRole("button", { name: "Open Question" }))
    await fireEvent.click(screen.getByRole("button", { name: "Close file" }))

    expect(onOpenSuspectAction).toHaveBeenNthCalledWith(
      1,
      suspectSelection,
      "search_suspect",
    )
    expect(onOpenSuspectAction).toHaveBeenNthCalledWith(
      2,
      suspectSelection,
      "interrogate",
    )
    expect(onCancelSuspect).toHaveBeenCalledWith(suspectSelection)
  })

  it("submits only a server-projected special actor option", async () => {
    const specialActorSelection = {
      actor: {
        id: "station-tail",
        name: "Station Tail",
        role: "counter-surveillance lookout",
      },
      location: { id: "51", name: "LAPD Headquarters" },
      options: [
        {
          id: "buy-off",
          label: "Buy off the lookout",
          action_cost: 1,
          scratch_cost: 2,
          choice_group: "tail-approach",
        },
        {
          id: "shadow-tail",
          label: "Shadow the lookout",
          action_cost: 2,
          scratch_cost: 0,
          choice_group: "tail-approach",
        },
      ],
    }
    const onInteractSpecialActor = vi.fn()
    const onCancelSpecialActor = vi.fn()

    render(ContextStack, {
      specialActorSelection,
      commandPending: false,
      commandError: null,
      commandStatus: false,
      connectionOnline: true,
      onInteractSpecialActor,
      onCancelSpecialActor,
    })

    expect(document.querySelector("#special-actor-slip")).toHaveTextContent(
      "counter-surveillance lookout · LAPD Headquarters",
    )
    expect(document.querySelector("#special-actor-slip")).not.toHaveTextContent(
      "private_case_cards",
    )
    expect(document.querySelector("#special-actor-choice-warning")).toHaveTextContent(
      "permanently closes the alternatives",
    )

    await fireEvent.click(screen.getByRole("button", { name: /Shadow the lookout/ }))
    await fireEvent.click(screen.getByRole("button", { name: "Close contact" }))

    expect(onInteractSpecialActor).toHaveBeenCalledWith(
      specialActorSelection,
      specialActorSelection.options[1],
    )
    expect(onCancelSpecialActor).toHaveBeenCalledWith(specialActorSelection)
  })

  it("routes the own Detective token through authorized field actions", async () => {
    const fieldSelection = {
      detective: {
        id: "detective-1",
        seat: 1,
        display_name: "Marlowe",
        actions_remaining: 3,
      },
      location: { id: "51", name: "LAPD Headquarters" },
      actionTypes: ["search_location", "analyze", "bribe_officer"],
    }
    const onOpenFieldAction = vi.fn()
    const onCancelField = vi.fn()

    render(ContextStack, {
      selection: null,
      fieldSelection,
      commandPending: false,
      commandError: null,
      commandStatus: false,
      connectionOnline: true,
      onOpenFieldAction,
      onCancelField,
    })

    expect(document.querySelector("#field-position-slip")).toHaveTextContent(
      "LAPD Headquarters",
    )
    expect(screen.queryByRole("button", { name: "Collect Kickback" })).not.toBeInTheDocument()

    await fireEvent.click(screen.getByRole("button", { name: "Analyze Case" }))
    await fireEvent.click(screen.getByRole("button", { name: "Open Officer Bribe" }))
    await fireEvent.click(screen.getByRole("button", { name: "Close position" }))

    expect(onOpenFieldAction).toHaveBeenNthCalledWith(1, fieldSelection, "analyze")
    expect(onOpenFieldAction).toHaveBeenNthCalledWith(2, fieldSelection, "bribe_officer")
    expect(onCancelField).toHaveBeenCalledWith(fieldSelection)
  })

  it("renders no empty paper without a selection or command message", () => {
    const { container } = render(ContextStack, {
      selection: null,
      origin: null,
      commandPending: false,
      commandError: null,
      commandStatus: false,
      connectionOnline: true,
      onConfirmMove: vi.fn(),
      onCancelMove: vi.fn(),
    })

    expect(container.querySelector("#context-stack")).not.toBeInTheDocument()
    expect(screen.queryByRole("status")).not.toBeInTheDocument()
    expect(screen.queryByRole("alert")).not.toBeInTheDocument()
  })
})
