import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"

import Home from "./Home.svelte"

describe("Home", () => {
  it("offers account entry from the public case desk", () => {
    render(Home, { signed_in: false })

    expect(document.querySelector("#home-case-desk.noir-wood-frame")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Open an account" })).toHaveAttribute(
      "href",
      "/users/register",
    )
    expect(screen.getByRole("link", { name: "Log in" })).toHaveAttribute(
      "href",
      "/users/log-in",
    )
  })

  it("sends an authenticated user to the case cabinet", () => {
    render(Home, { signed_in: true })

    expect(screen.getByRole("link", { name: "Open case cabinet" })).toHaveAttribute(
      "href",
      "/dashboard",
    )
  })
})
