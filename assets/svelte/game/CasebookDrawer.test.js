import { fireEvent, render, screen, waitFor } from "@testing-library/svelte"
import { createRawSnippet } from "svelte"
import { describe, expect, it, vi } from "vitest"
import CasebookDrawer from "./CasebookDrawer.svelte"

describe("CasebookDrawer", () => {
  it("labels the open casebook and exposes a close action", async () => {
    const onClose = vi.fn()
    render(CasebookDrawer, { open: true, title: "Evidence", onClose })

    expect(screen.getByRole("complementary", { name: "Evidence" })).toBeVisible()
    await fireEvent.click(screen.getByRole("button", { name: "Close casebook" }))
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it("does not leave a hidden complementary landmark when closed", () => {
    render(CasebookDrawer, { open: false, title: "Evidence", onClose: vi.fn() })

    expect(screen.queryByRole("complementary", { name: "Evidence" })).not.toBeInTheDocument()
  })

  it("renders the selected casebook page through its snippet slot", () => {
    const children = createRawSnippet(() => ({
      render: () => '<section id="evidence-page">Private evidence</section>',
    }))

    render(CasebookDrawer, {
      open: true,
      title: "Evidence",
      onClose: vi.fn(),
      children,
    })

    expect(screen.getByText("Private evidence")).toBeInTheDocument()
    expect(document.querySelector("#casebook-drawer-content #evidence-page")).toBeTruthy()
  })

  it("returns focus to the control that opened the drawer", async () => {
    const opener = document.createElement("button")
    opener.textContent = "Open evidence"
    document.body.append(opener)
    opener.focus()

    render(CasebookDrawer, { open: true, title: "Evidence", onClose: vi.fn() })

    await fireEvent.click(screen.getByRole("button", { name: "Close casebook" }))

    await waitFor(() => expect(opener).toHaveFocus())
    opener.remove()
  })

  it("closes from Escape without handling game commands", async () => {
    const onClose = vi.fn()
    render(CasebookDrawer, { open: true, title: "Question", onClose })

    await fireEvent.keyDown(screen.getByRole("complementary", { name: "Question" }), {
      key: "Escape",
    })

    expect(onClose).toHaveBeenCalledTimes(1)
  })
})
