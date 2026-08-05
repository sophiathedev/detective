export function caseCardCodeFromPrivateEvent(payload = {}) {
  if (payload.type === "bribe_result") {
    return payload.case_card?.code ?? null
  }

  if (
    ["search_result", "suspect_response", "challenge_resolved", "snitch_result"].includes(
      payload.type,
    )
  ) {
    return payload.case_cards?.find((card) => card?.code)?.code ?? null
  }

  return null
}
