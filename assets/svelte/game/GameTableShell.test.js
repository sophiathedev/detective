import { render, screen } from "@testing-library/svelte"
import { createRawSnippet } from "svelte"
import { describe, expect, it } from "vitest"

import GameTableShell from "./GameTableShell.svelte"

const snippet = (text) => createRawSnippet(() => ({ render: () => `<span>${text}</span>` }))

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
    })

    expect(document.querySelector("#game-table-shell.noir-game-table")).toBeInTheDocument()
    expect(screen.getByRole("main")).toContainElement(document.querySelector("#game-map-region"))
    expect(document.querySelector("#game-detective-rail-region")).toHaveTextContent("players")
    expect(document.querySelector("#game-chisel-region")).toHaveTextContent("chisel")
    expect(document.querySelector("#game-context-region")).toHaveTextContent("context")
    expect(document.querySelector("#game-action-region")).toHaveTextContent("actions")
    expect(document.querySelector("#game-overlay-region")).toHaveTextContent("overlay")
    expect(document.querySelector("#game-phase-plaque")).toHaveTextContent("Marlowe")
  })
})
