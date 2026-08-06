import { createRawSnippet } from "svelte"
import { fireEvent, render, screen, waitFor } from "@testing-library/svelte"
import { describe, expect, it, vi } from "vitest"

import CasebookOverlay from "./CasebookOverlay.svelte"

const content = createRawSnippet(() => ({ render: () => "<p>Private evidence</p>" }))

describe("CasebookOverlay", () => {
  it("labels the dialog, renders its page, and closes with Escape", async () => {
    const onClose = vi.fn()

    render(CasebookOverlay, {
      open: true,
      title: "Evidence",
      folioLabel: "Chisel private casebook",
      page: "evidence",
      pages: [{ id: "evidence", label: "Evidence" }],
      onSelectPage: vi.fn(),
      onClose,
      children: content,
    })

    expect(screen.getByRole("dialog", { name: "Evidence" })).toBeInTheDocument()
    expect(screen.getByText("Chisel private casebook")).toBeInTheDocument()
    expect(screen.getByText("Private evidence")).toBeInTheDocument()
    await fireEvent.keyDown(window, { key: "Escape" })
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it("changes pages without sending a game command", async () => {
    const onSelectPage = vi.fn()

    render(CasebookOverlay, {
      open: true,
      title: "Evidence",
      page: "evidence",
      pages: [
        { id: "evidence", label: "Evidence" },
        { id: "history", label: "History" },
      ],
      onSelectPage,
      onClose: vi.fn(),
      children: content,
    })

    await fireEvent.click(screen.getByRole("button", { name: "History" }))
    expect(onSelectPage).toHaveBeenCalledWith("history")
  })

  it("returns focus to the control that opened the overlay", async () => {
    const opener = document.createElement("button")
    opener.textContent = "Open casebook"
    document.body.append(opener)
    opener.focus()

    render(CasebookOverlay, {
      open: true,
      title: "Evidence",
      page: "evidence",
      pages: [],
      onSelectPage: vi.fn(),
      onClose: vi.fn(),
      children: content,
    })

    await fireEvent.click(screen.getByRole("button", { name: "Close casebook" }))
    await waitFor(() => expect(opener).toHaveFocus())
    opener.remove()
  })

  it("keeps keyboard focus inside the open folio", async () => {
    render(CasebookOverlay, {
      open: true,
      title: "Evidence",
      page: "evidence",
      pages: [{ id: "evidence", label: "Evidence" }],
      onSelectPage: vi.fn(),
      onClose: vi.fn(),
      children: content,
    })

    const outside = document.createElement("button")
    outside.textContent = "Underlying map control"
    document.body.append(outside)
    outside.focus()

    await fireEvent.keyDown(window, { key: "Tab" })
    expect(screen.getByRole("button", { name: "Close casebook" })).toHaveFocus()
    outside.remove()
  })

  it("leaves no hidden dialog when closed", () => {
    render(CasebookOverlay, {
      open: false,
      title: "Evidence",
      page: "evidence",
      pages: [],
      onSelectPage: vi.fn(),
      onClose: vi.fn(),
      children: content,
    })

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument()
  })
})
