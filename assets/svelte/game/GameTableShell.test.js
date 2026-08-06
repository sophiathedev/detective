import { fireEvent, render, screen, waitFor } from "@testing-library/svelte"
import { createRawSnippet } from "svelte"
import { afterEach, describe, expect, it, vi } from "vitest"

import GameTableShell from "./GameTableShell.svelte"

const snippet = (text) => createRawSnippet(() => ({ render: () => `<span>${text}</span>` }))

afterEach(() => {
  delete HTMLElement.prototype.requestFullscreen
  delete document.exitFullscreen
  delete document.fullscreenElement
})

describe("GameTableShell", () => {
  it("keeps the map primary and exposes every table landmark", () => {
    render(GameTableShell, {
      phase: "detective_turn",
      day: 8,
      daysRemaining: 6,
      activeDetectiveName: "Marlowe",
      connectionState: "online",
      version: 19,
      detectiveRail: snippet("players"),
      chiselConsole: snippet("chisel"),
      mapStage: snippet("map"),
      contextStack: snippet("context"),
      actionRail: snippet("actions"),
      overlay: snippet("overlay"),
      csrfToken: "test-csrf-token",
    })

    expect(document.querySelector("#game-table-shell.noir-game-table")).toBeInTheDocument()
    expect(document.querySelector(".noir-table-lighting")).toHaveAttribute("aria-hidden", "true")
    expect(screen.getByRole("main")).toContainElement(document.querySelector("#game-map-region"))
    expect(document.querySelector("#game-detective-rail-region")).toHaveTextContent("players")
    expect(document.querySelector("#game-chisel-region")).toHaveTextContent("chisel")
    expect(document.querySelector("#game-context-region")).toHaveTextContent("context")
    expect(document.querySelector("#game-action-region")).toHaveTextContent("actions")
    expect(document.querySelector("#game-overlay-region")).toHaveTextContent("overlay")
    expect(document.querySelector("#game-phase-plaque")).toHaveTextContent("Marlowe")
    expect(document.querySelector("#game-return-dashboard")).toHaveAttribute(
      "href",
      "/dashboard",
    )
    expect(document.querySelector("#game-account-settings")).toHaveAttribute(
      "href",
      "/users/settings",
    )
    expect(document.querySelector("#game-account-log-out")).toHaveAttribute(
      "data-method",
      "delete",
    )
    expect(document.querySelector("#game-account-log-out")).toHaveAttribute(
      "data-to",
      "/users/log-out",
    )
    expect(document.querySelector("#game-account-log-out")).toHaveAttribute(
      "data-csrf",
      "test-csrf-token",
    )
    expect(document.querySelector("#game-locale-en")).toHaveAttribute("aria-current", "true")
    expect(document.querySelector("#game-locale-vi")).toHaveAttribute(
      "data-method",
      "post",
    )
    expect(document.querySelector("#game-locale-vi")).toHaveAttribute(
      "data-csrf",
      "test-csrf-token",
    )
    expect(document.querySelector("#game-locale-vi")).toHaveAttribute(
      "data-to",
      "/locale/vi?return_to=%2Fdashboard",
    )
  })

  it("enters and exits fullscreen from the case menu", async () => {
    let fullscreenElement = null
    const requestFullscreen = vi.fn(async function () {
      fullscreenElement = this
      document.dispatchEvent(new Event("fullscreenchange"))
    })
    const exitFullscreen = vi.fn(async () => {
      fullscreenElement = null
      document.dispatchEvent(new Event("fullscreenchange"))
    })

    Object.defineProperty(HTMLElement.prototype, "requestFullscreen", {
      configurable: true,
      value: requestFullscreen,
    })
    Object.defineProperty(document, "exitFullscreen", {
      configurable: true,
      value: exitFullscreen,
    })
    Object.defineProperty(document, "fullscreenElement", {
      configurable: true,
      get: () => fullscreenElement,
    })

    render(GameTableShell, {
      phase: "detective_turn",
      day: 1,
      daysRemaining: 6,
      activeDetectiveName: "Marlowe",
      connectionState: "online",
      version: 19,
    })

    await fireEvent.click(screen.getByLabelText("Open case menu"))
    const button = screen.getByRole("button", { name: /Fill the screen/ })
    await waitFor(() => expect(button).toBeEnabled())
    await fireEvent.click(button)

    await waitFor(() => {
      expect(requestFullscreen).toHaveBeenCalledTimes(1)
      expect(button).toHaveAttribute("aria-pressed", "true")
      expect(button).toHaveTextContent("Exit fullscreen")
    })

    await fireEvent.click(screen.getByLabelText("Open case menu"))
    await fireEvent.click(screen.getByRole("button", { name: /Exit fullscreen/ }))

    await waitFor(() => {
      expect(exitFullscreen).toHaveBeenCalledTimes(1)
      expect(button).toHaveAttribute("aria-pressed", "false")
    })
  })
})
