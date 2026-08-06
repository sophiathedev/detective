import { fireEvent, render, screen } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"

import PauseCurtain from "./PauseCurtain.svelte"

describe("PauseCurtain", () => {
  it("shows offline players and exposes resume only to authority", async () => {
    const onResume = vi.fn()

    render(PauseCurtain, {
      active: true,
      reason: "player_disconnected",
      offlinePlayers: [{ id: "d1", display_name: "Marlowe" }],
      canResume: true,
      commandPending: false,
      commandError: null,
      onResume,
    })

    expect(screen.getByRole("dialog", { name: "Case paused" })).toHaveTextContent("Marlowe")
    expect(screen.getByRole("dialog", { name: "Case paused" })).toHaveTextContent(
      "left the table",
    )
    expect(screen.queryByText("player_disconnected")).not.toBeInTheDocument()
    await fireEvent.click(screen.getByRole("button", { name: "Resume game" }))
    expect(onResume).toHaveBeenCalledTimes(1)
  })

  it("shows waiting copy instead of authority controls", () => {
    render(PauseCurtain, {
      active: true,
      reason: "Chisel disconnected",
      offlinePlayers: [],
      canResume: false,
      commandPending: false,
      commandError: null,
      onResume: vi.fn(),
    })

    expect(screen.getByText(/Chisel will reopen the case/i)).toBeInTheDocument()
    expect(screen.queryByRole("button", { name: "Resume game" })).not.toBeInTheDocument()
  })

  it("renders nothing while inactive", () => {
    render(PauseCurtain, {
      active: false,
      reason: null,
      offlinePlayers: [],
      canResume: false,
      commandPending: false,
      commandError: null,
      onResume: vi.fn(),
    })

    expect(screen.queryByRole("dialog", { name: "Case paused" })).not.toBeInTheDocument()
  })

  it("keeps keyboard focus inside the blocking curtain", async () => {
    render(PauseCurtain, {
      active: true,
      reason: "Detective disconnected",
      offlinePlayers: [],
      canResume: true,
      commandPending: false,
      commandError: null,
      onResume: vi.fn(),
    })

    const outside = document.createElement("button")
    outside.textContent = "Underlying map control"
    document.body.append(outside)
    outside.focus()

    await fireEvent.keyDown(window, { key: "Tab" })
    expect(screen.getByRole("button", { name: "Resume game" })).toHaveFocus()
    outside.remove()
  })
})
