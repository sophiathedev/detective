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
