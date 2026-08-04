import { render, screen } from "@testing-library/svelte"
import { createRawSnippet } from "svelte"
import { describe, expect, it } from "vitest"

import PaperSheet from "./PaperSheet.svelte"
import PortraitToken from "./PortraitToken.svelte"
import StatusStamp from "./StatusStamp.svelte"
import WoodFrame from "./WoodFrame.svelte"

const snippet = (text) => createRawSnippet(() => ({ render: () => text }))

describe("noir visual primitives", () => {
  it("preserves requested semantic elements and labels", () => {
    render(WoodFrame, {
      as: "section",
      id: "case-frame",
      labelledby: "case-title",
      children: snippet("Case"),
    })

    render(PaperSheet, {
      as: "article",
      id: "case-paper",
      labelledby: "case-title",
      children: snippet("Paper"),
    })

    expect(document.querySelector("section#case-frame.noir-wood-frame")).toHaveAttribute(
      "aria-labelledby",
      "case-title",
    )
    expect(document.querySelector("article#case-paper.noir-paper-sheet")).toHaveAttribute(
      "aria-labelledby",
      "case-title",
    )
  })

  it("prints status text and an accessible textured portrait", () => {
    render(StatusStamp, { tone: "ready", children: snippet("Ready") })
    render(PortraitToken, { name: "Mara Voss", role: "detective", seat: 2, size: "md" })

    expect(screen.getByText("Ready")).toHaveClass("noir-status-stamp-ready")
    expect(screen.getByRole("img", { name: "Detective portrait for Mara Voss" })).toHaveAttribute(
      "src",
      "/images/ui/noir/portraits/detective-2.webp",
    )
  })
})
