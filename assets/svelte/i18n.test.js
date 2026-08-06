import { describe, expect, it } from "vitest"

import { createI18n, normalizeLocale, translate } from "./i18n"

describe("frontend i18n", () => {
  it("translates Vietnamese labels and interpolates values", () => {
    expect(translate("vi", "Good evening, {name}.", { name: "Lan" })).toBe(
      "Ca trực bắt đầu, Lan.",
    )
  })

  it("keeps English as the source locale and falls back safely", () => {
    expect(createI18n("en").t("Dashboard")).toBe("Dashboard")
    expect(translate("vi", "Authored case text")).toBe("Authored case text")
    expect(normalizeLocale("fr")).toBe("en")
  })
})
