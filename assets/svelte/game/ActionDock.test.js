import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"
import ActionDock from "./ActionDock.svelte"

const destination = {
  id: "48",
  name: "Bradbury Building",
  district_ids: ["central_la"],
}

const origin = {
  id: "51",
  name: "LAPD Headquarters",
  district_ids: ["central_la"],
}

const baseProps = {
  availableActions: ["move", "analyze", "end_turn"],
  selection: { type: "move", location: destination },
  origin,
  commandPending: false,
  commandError: null,
  connectionOnline: true,
  onConfirmMove: vi.fn(),
  onCancelMove: vi.fn(),
  onAction: vi.fn(),
}

describe("ActionDock", () => {
  it("does not dispatch movement until the selected destination is confirmed", async () => {
    const onConfirmMove = vi.fn()

    render(ActionDock, { ...baseProps, onConfirmMove })

    expect(onConfirmMove).not.toHaveBeenCalled()
    expect(screen.getByText("LAPD Headquarters")).toBeInTheDocument()
    expect(screen.getByText("Bradbury Building")).toBeInTheDocument()

    await fireEvent.click(screen.getByRole("button", { name: "Confirm Move" }))

    expect(onConfirmMove).toHaveBeenCalledTimes(1)
  })

  it("dispatches only exact server-projected non-map actions", async () => {
    const onAction = vi.fn()
    const projectedActions = [
      ["search_location", "Search Location"],
      ["search_suspect", "Search Suspect"],
      ["interrogate", "Question Suspect"],
      ["analyze", "Analyze"],
      ["kickback", "Kickback"],
      ["accuse", "Accuse"],
      ["submit_final_guess", "Seal Final Guess"],
      ["end_turn", "End Turn"],
    ]

    render(ActionDock, {
      ...baseProps,
      availableActions: new Set(projectedActions.map(([id]) => id)),
      selection: null,
      onAction,
    })

    for (const [, label] of projectedActions) {
      await fireEvent.click(screen.getByRole("button", { name: label }))
    }

    expect(onAction.mock.calls).toEqual(projectedActions.map(([id]) => [id]))
  })

  it("does not invent actions omitted by the server projection", () => {
    render(ActionDock, {
      ...baseProps,
      availableActions: ["analyze"],
      selection: null,
    })

    expect(screen.getByRole("button", { name: "Analyze" })).toBeInTheDocument()
    expect(screen.queryByRole("button", { name: "Kickback" })).not.toBeInTheDocument()
    expect(screen.queryByRole("button", { name: "End Turn" })).not.toBeInTheDocument()
    expect(screen.queryByRole("button", { name: "Confirm Move" })).not.toBeInTheDocument()
  })

  it("keeps selection cancelable but blocks confirmation while offline or dispatching", async () => {
    const onConfirmMove = vi.fn()
    const onCancelMove = vi.fn()

    const { rerender } = render(ActionDock, {
      ...baseProps,
      connectionOnline: false,
      onConfirmMove,
      onCancelMove,
    })

    expect(screen.getByRole("button", { name: "Confirm Move" })).toBeDisabled()
    await fireEvent.click(screen.getByRole("button", { name: "Cancel Move" }))
    expect(onCancelMove).toHaveBeenCalledTimes(1)

    await rerender({
      ...baseProps,
      commandPending: true,
      onConfirmMove,
      onCancelMove,
    })

    expect(screen.getByRole("button", { name: "Dispatching car" })).toBeDisabled()
    expect(screen.getByRole("status")).toHaveTextContent("Dispatching car")
  })

  it("announces a completed stale-version resynchronization as status copy", () => {
    render(ActionDock, {
      ...baseProps,
      selection: null,
      commandError: "Game state changed; map resynchronized",
      commandStatus: true,
    })

    expect(screen.getByRole("status")).toHaveTextContent(
      "Game state changed; map resynchronized",
    )
    expect(screen.queryByRole("alert")).not.toBeInTheDocument()
  })

  it("labels free placement without inventing an action cost", () => {
    render(ActionDock, {
      ...baseProps,
      availableActions: ["place"],
      selection: { type: "place", location: origin },
      origin: null,
    })

    expect(screen.getByRole("button", { name: "Confirm Placement" })).toBeInTheDocument()
    expect(screen.queryByText(/\b\d+\s*AP\b/i)).not.toBeInTheDocument()
  })
})
