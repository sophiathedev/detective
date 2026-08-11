function interpolate(message, values = {}) {
  return message.replace(/\{([a-zA-Z0-9_]+)\}/g, (match, key) =>
    Object.hasOwn(values, key) ? String(values[key]) : match,
  )
}

export function buildImmediateActionPrompt(
  action,
  { actionsRemaining = 0, playerCount = 0, t = interpolate } = {},
) {
  const prompts = {
    analyze: {
      type: "analyze",
      stamp: t("ANALYZE"),
      kicker: t("Desk work"),
      title: t("Gain $1 Scratch"),
      description: t("Spend 1 Action to think through the case. {count} Actions will remain.", {
        count: Math.max(actionsRemaining - 1, 0),
      }),
      confirmLabel: t("Analyze case"),
    },
    kickback: {
      type: "kickback",
      stamp: t("KICKBACK"),
      kicker: t("Mob Joint collection"),
      title: t("Collect ${amount} Scratch", { amount: playerCount }),
      description: t("Spend 1 Action. Kickback is legal once per Day and only at a Mob Joint."),
      confirmLabel: t("Collect kickback"),
    },
    skip_free_question: {
      type: "skip_free_question",
      stamp: t("DECLINE"),
      kicker: t("New suspect lead"),
      title: t("Decline the free question"),
      description: t("Discard this free opportunity. A later Question action will cost 1 Action."),
      confirmLabel: t("Decline question"),
    },
    end_turn: {
      type: "end_turn",
      stamp: t("END TURN"),
      kicker: t("Detective handoff"),
      title:
        actionsRemaining > 0
          ? t(actionsRemaining === 1 ? "Forfeit 1 remaining Action" : "Forfeit {count} remaining Actions", { count: actionsRemaining })
          : t("Close this Detective turn"),
      description: t("Control passes to the next Detective. After the final Detective, the Day advances."),
      confirmLabel: t("End turn"),
    },
    concede_game: {
      type: "concede_game",
      stamp: t("CONCEDE"),
      kicker: t("Chisel authority"),
      title: t("Concede the investigation"),
      description: t("This immediately closes the case and awards a team victory to every Detective. The action cannot be undone."),
      confirmLabel: t("Concede and release solution"),
    },
  }

  return prompts[action] ?? null
}
