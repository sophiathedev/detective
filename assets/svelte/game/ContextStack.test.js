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

    render(ContextStack, {
      selection,
      origin: { id: "51", name: "LAPD Headquarters" },
      commandPending: false,
      commandError: null,
      commandStatus: false,
      connectionOnline: true,
      onConfirmMove,
      onCancelMove: vi.fn(),
    })

    expect(onConfirmMove).not.toHaveBeenCalled()
    expect(screen.getByText("Bradbury Building")).toBeInTheDocument()
    await fireEvent.click(screen.getByRole("button", { name: "Confirm Move" }))
    expect(onConfirmMove).toHaveBeenCalledWith(selection)
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
