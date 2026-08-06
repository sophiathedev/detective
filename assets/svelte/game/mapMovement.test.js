import { describe, expect, it } from "vitest"

import { directMapLocationIds, directMapMovementType } from "./mapMovement"

describe("direct map movement", () => {
  it("makes legal destinations clickable without selecting Move first", () => {
    const movementType = directMapMovementType(null, ["move", "search_location"])

    expect(movementType).toBe("move")
    expect(directMapLocationIds(movementType, ["station"], ["alley", "hotel"])).toEqual([
      "alley",
      "hotel",
    ])
  })

  it("uses a starting precinct only before the Detective enters the board", () => {
    const movementType = directMapMovementType(null, new Set(["place"]))

    expect(movementType).toBe("place")
    expect(directMapLocationIds(movementType, ["central", "hollywood"], ["alley"])).toEqual([
      "central",
      "hollywood",
    ])
  })
})
