export function directMapMovementType(activeAction, availableActions = []) {
  const actions = availableActions instanceof Set ? availableActions : new Set(availableActions)

  if (activeAction === "place" || activeAction === "move") return activeAction
  if (actions.has("place")) return "place"
  if (actions.has("move")) return "move"

  return null
}

export function directMapLocationIds(
  movementType,
  placementLocationIds = [],
  moveLocationIds = [],
) {
  if (movementType === "place") return [...placementLocationIds]
  if (movementType === "move") return [...moveLocationIds]

  return []
}
