defmodule DetectiveWeb.GameNewLiveTest do
  use DetectiveWeb.ConnCase, async: true

  import Detective.AccountsFixtures
  import Detective.CasesFixtures
  import LiveSvelte.Test
  import Phoenix.LiveViewTest

  alias Detective.Games.Game
  alias Detective.Repo

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/new")
  end

  test "renders published case options", %{conn: conn} do
    user = user_fixture()
    version = case_version_fixture()

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/games/new")

    component = get_svelte(view, id: "create-game-frontend")
    assert component.name == "CreateGame"

    assert [%{"value" => value, "label" => label}] = component.props["case_options"]
    assert value == version.id
    assert label =~ version.case_file.title
  end

  test "creates a room and reveals the raw invite once", %{conn: conn} do
    user = user_fixture()
    version = case_version_fixture()
    logged_in_conn = log_in_user(conn, user)
    {:ok, view, _html} = live(logged_in_conn, ~p"/games/new")

    render_submit(view, "save", %{
      "game" => %{
        "title" => "Midnight table",
        "case_version_id" => version.id,
        "max_detectives" => "3",
        "invite_hours" => "24"
      }
    })

    created_room = get_svelte(view, id: "create-game-frontend").props["created_room"]
    assert created_room["lobby_path"] =~ ~r{^/games/[0-9a-f-]+/lobby$}
    refute created_room["lobby_path"] =~ "invite"
    assert created_room["invite_url"] =~ "/invites/"
    assert Repo.aggregate(Game, :count) == 1
  end
end
