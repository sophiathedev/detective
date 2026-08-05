import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"

import Invite from "./Invite.svelte"

const invite = {
  room_code: "ABC234",
  game_title: "Midnight Bureau",
  case_title: "The Pendleton Murders",
  host_name: "Elizabeth",
  detective_count: 1,
  max_detectives: 4,
  places_left: 3,
  membership_status: null,
}

describe("Invite", () => {
  it("renders a valid summons with an acceptance seal", () => {
    render(Invite, { invite, error: null })

    expect(document.querySelector("#invite-summons.noir-paper-sheet")).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Accept case invitation" })).toHaveAttribute(
      "id",
      "accept-game-invite",
    )
    expect(screen.getByText("1/4")).toBeInTheDocument()
  })

  it("stamps an unavailable invitation without an accept button", () => {
    render(Invite, { invite: null, error: "This invitation is no longer available." })

    expect(screen.getByText("Invitation closed")).toHaveClass("noir-status-stamp-danger")
    expect(screen.queryByRole("button", { name: /Accept/i })).not.toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Back to dashboard" })).toBeInTheDocument()
  })
})
