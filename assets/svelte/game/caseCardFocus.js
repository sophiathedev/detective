export function caseCardCodeFromPrivateEvent(payload = {}) {
  if (payload.type === "bribe_result") {
    return payload.case_card?.code ?? null
  }

  if (payload.type === "search_result") {
    return payload.case_cards?.find((card) => card?.code)?.code ?? null
  }

  return null
}
