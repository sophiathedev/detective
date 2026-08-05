export function buildImmediateActionPrompt(
  action,
  { actionsRemaining = 0, playerCount = 0 } = {},
) {
  const prompts = {
    analyze: {
      type: "analyze",
      stamp: "ANALYZE",
      kicker: "Desk work",
      title: "Gain $1 Scratch",
      description: `Spend 1 Action to think through the case. ${Math.max(actionsRemaining - 1, 0)} Actions will remain.`,
      confirmLabel: "Analyze case",
    },
    kickback: {
      type: "kickback",
      stamp: "KICKBACK",
      kicker: "Mob Joint collection",
      title: `Collect $${playerCount} Scratch`,
      description: "Spend 1 Action. Kickback is legal once per Day and only at a Mob Joint.",
      confirmLabel: "Collect kickback",
    },
    skip_free_question: {
      type: "skip_free_question",
      stamp: "DECLINE",
      kicker: "New suspect lead",
      title: "Decline the free question",
      description: "Discard this free opportunity. A later Question action will cost 1 Action.",
      confirmLabel: "Decline question",
    },
    end_turn: {
      type: "end_turn",
      stamp: "END TURN",
      kicker: "Detective handoff",
      title:
        actionsRemaining > 0
          ? `Forfeit ${actionsRemaining} remaining Action${actionsRemaining === 1 ? "" : "s"}`
          : "Close this Detective turn",
      description:
        "Control passes to the next Detective. After the final Detective, the Day advances.",
      confirmLabel: "End turn",
    },
  }

  return prompts[action] ?? null
}
