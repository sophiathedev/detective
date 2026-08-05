import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"

import CreateGame from "./CreateGame.svelte"

const baseProps = {
  form: {
    fields: { title: "", case_version_id: "", max_detectives: "4", invite_hours: "24" },
    errors: {},
  },
  case_options: [{ value: "v1", label: "Pendleton v1", description: "Public synopsis" }],
  global_error: null,
  created_room: null,
}

describe("CreateGame", () => {
  it("renders a semantic case-opening form", () => {
    render(CreateGame, baseProps)

    expect(document.querySelector("#create-game-document.noir-paper-sheet")).toBeInTheDocument()
    expect(screen.getByRole("textbox", { name: "Room name" })).toHaveAttribute(
      "name",
      "game[title]",
    )
    expect(screen.getByRole("radio", { name: /Pendleton v1/i })).toHaveAttribute(
      "name",
      "game[case_version_id]",
    )
    expect(screen.queryByRole("option", { name: "1 detective" })).not.toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Seal and create room" })).toBeEnabled()
  })

  it("renders the raw invitation only in the created-room sheet", () => {
    render(CreateGame, {
      ...baseProps,
      created_room: {
        room_code: "ABC234",
        invite_url: "http://localhost/invites/raw-token",
        lobby_path: "/games/g1/lobby",
      },
    })

    expect(screen.getByLabelText("Invitation URL")).toHaveValue(
      "http://localhost/invites/raw-token",
    )
    expect(screen.getByRole("link", { name: "Enter lobby" })).toHaveAttribute(
      "href",
      "/games/g1/lobby",
    )
  })
})
