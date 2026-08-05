import { describe, expect, it } from "vitest"

import { caseCardCodeFromPrivateEvent } from "./caseCardFocus"

describe("caseCardCodeFromPrivateEvent", () => {
  it("selects the first projected Case card from a private Search result", () => {
    expect(
      caseCardCodeFromPrivateEvent({
        type: "search_result",
        case_cards: [
          { id: "sealed-ledger", code: "B" },
          { id: "hidden-key", code: "D" },
        ],
      }),
    ).toBe("B")
  })

  it("selects the projected Case card from a private Bribe result", () => {
    expect(
      caseCardCodeFromPrivateEvent({
        type: "bribe_result",
        case_card: { id: "sealed-ledger", code: "B" },
      }),
    ).toBe("B")
  })

  it.each(["suspect_response", "challenge_resolved", "snitch_result"])(
    "selects the first linked Case card from a %s event",
    (type) => {
      expect(
        caseCardCodeFromPrivateEvent({
          type,
          case_cards: [{ id: "sealed-ledger", code: "B" }],
        }),
      ).toBe("B")
    },
  )

  it("does not infer a card from unrelated or incomplete private events", () => {
    expect(caseCardCodeFromPrivateEvent({ type: "search_result", case_cards: [] })).toBeNull()
    expect(caseCardCodeFromPrivateEvent({ type: "bribe_result" })).toBeNull()
    expect(caseCardCodeFromPrivateEvent({ type: "challenge_resolved" })).toBeNull()
    expect(caseCardCodeFromPrivateEvent({ type: "scratch_updated", received: 2 })).toBeNull()
  })
})
