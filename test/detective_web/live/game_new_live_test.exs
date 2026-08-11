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

  test "validates fields and preserves invitation expiry", %{conn: conn} do
    user = user_fixture()
    version = case_version_fixture()
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/games/new")

    render_change(view, "validate", %{
      "game" => %{
        "title" => "",
        "case_version_id" => version.id,
        "max_detectives" => "9",
        "invite_hours" => "72"
      }
    })

    form = get_svelte(view, id: "create-game-frontend").props["form"]
    assert form["fields"]["invite_hours"] == "72"
    assert Map.has_key?(form["errors"], "title")
    assert Map.has_key?(form["errors"], "max_detectives")
  end

  test "reports stale case versions and invalid invitation expiry", %{conn: conn} do
    user = user_fixture()
    unavailable_version = case_version_fixture(%{published_at: nil})
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/games/new")

    render_submit(view, "save", %{
      "game" => %{
        "title" => "Unavailable case",
        "case_version_id" => unavailable_version.id,
        "max_detectives" => "2",
        "invite_hours" => "24"
      }
    })

    component = get_svelte(view, id: "create-game-frontend")

    assert component.props["global_error"] ==
             "That case is no longer available. Choose another published case."

    published_version = case_version_fixture()

    render_submit(view, "save", %{
      "game" => %{
        "title" => "Invalid invitation",
        "case_version_id" => published_version.id,
        "max_detectives" => "2",
        "invite_hours" => "2"
      }
    })

    component = get_svelte(view, id: "create-game-frontend")
    assert component.props["global_error"] == "Choose a valid invitation expiry."
    assert component.props["form"]["fields"]["invite_hours"] == "2"
  end

  test "returns field errors when creation changeset is invalid", %{conn: conn} do
    user = user_fixture()
    version = case_version_fixture()
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/games/new")

    render_submit(view, "save", %{
      "game" => %{
        "title" => "",
        "case_version_id" => version.id,
        "max_detectives" => "2",
        "invite_hours" => "24"
      }
    })

    form = get_svelte(view, id: "create-game-frontend").props["form"]
    assert Map.has_key?(form["errors"], "title")
  end
end
