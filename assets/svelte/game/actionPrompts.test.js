import { describe, expect, it } from "vitest"

import { buildImmediateActionPrompt } from "./actionPrompts"

describe("buildImmediateActionPrompt", () => {
  it("shows the fixed Analyze exchange", () => {
    const prompt = buildImmediateActionPrompt("analyze", { actionsRemaining: 3, playerCount: 4 })

    expect(prompt.title).toBe("Gain $1 Scratch")
    expect(prompt.description).toContain("2 Actions will remain")
  })

  it("calculates Kickback from Detectives plus the Chisel", () => {
    const prompt = buildImmediateActionPrompt("kickback", {
      actionsRemaining: 2,
      playerCount: 4,
    })

    expect(prompt.title).toBe("Collect $4 Scratch")
    expect(prompt.description).toContain("once per Day")
  })

  it("warns how many actions End Turn forfeits", () => {
    expect(
      buildImmediateActionPrompt("end_turn", { actionsRemaining: 1 }).title,
    ).toBe("Forfeit 1 remaining Action")
    expect(
      buildImmediateActionPrompt("end_turn", { actionsRemaining: 3 }).title,
    ).toBe("Forfeit 3 remaining Actions")
  })
})
