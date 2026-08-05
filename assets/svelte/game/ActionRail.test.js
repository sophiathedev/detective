import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"

import ActionRail from "./ActionRail.svelte"

describe("ActionRail", () => {
  it("renders projected game actions plus the casebook utility", async () => {
    const onChooseAction = vi.fn()
    const onAction = vi.fn()
    const onOpenCasebook = vi.fn()

    render(ActionRail, {
      availableActions: ["move", "analyze", "bribe_detective", "end_turn"],
      activeAction: null,
      commandPending: false,
      connectionOnline: true,
      onChooseAction,
      onAction,
      onOpenCasebook,
    })

    await fireEvent.click(screen.getByRole("button", { name: "Move" }))
    await fireEvent.click(screen.getByRole("button", { name: "Analyze" }))
    await fireEvent.click(screen.getByRole("button", { name: "Bribe Detective" }))
    await fireEvent.click(screen.getByRole("button", { name: "Casebook" }))

    expect(onChooseAction).toHaveBeenCalledWith("move")
    expect(onAction).toHaveBeenCalledWith("analyze")
    expect(onAction).toHaveBeenCalledWith("bribe_detective")
    expect(onOpenCasebook).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole("button", { name: "Kickback" })).not.toBeInTheDocument()
  })

  it("keeps the casebook readable while blocking commands offline", () => {
    render(ActionRail, {
      availableActions: ["move", "analyze"],
      activeAction: "move",
      commandPending: false,
      connectionOnline: false,
      onChooseAction: vi.fn(),
      onAction: vi.fn(),
      onOpenCasebook: vi.fn(),
    })

    expect(screen.getByRole("button", { name: "Move" })).toBeDisabled()
    expect(screen.getByRole("button", { name: "Analyze" })).toBeDisabled()
    expect(screen.getByRole("button", { name: "Casebook" })).toBeEnabled()
  })
})
