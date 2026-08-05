defmodule DetectiveWeb.DashboardLiveTest do
  use DetectiveWeb.ConnCase, async: true

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import LiveSvelte.Test
  import Phoenix.LiveViewTest

  test "requires an authenticated user", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
  end

  test "renders the signed-in user's empty game desk", %{conn: conn} do
    user = user_fixture(display_name: "Mara Voss")

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/dashboard")

    assert has_element?(view, "#dashboard-frontend")

    component = get_svelte(view, id: "dashboard-frontend")
    assert component.name == "Dashboard"
    assert component.props["display_name"] == "Mara Voss"
    assert component.props["games"] == %{"active" => 0, "finished" => 0, "waiting" => 0}
    assert component.props["dossiers"] == %{"active" => [], "finished" => [], "waiting" => []}
    refute Map.has_key?(component.props, "email")
  end

  test "projects allow-listed case dossiers with verified paths", %{conn: conn} do
    user = user_fixture(display_name: "Mara Voss")
    %{game: game} = game_fixture(user, %{title: "Midnight Bureau", max_detectives: 4})

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/dashboard")

    component = get_svelte(view, id: "dashboard-frontend")

    assert %{"waiting" => waiting, "active" => [], "finished" => []} =
             component.props["dossiers"]

    assert [%{"role" => "chisel"} = dossier] = waiting
    assert dossier["id"] == game.id
    assert dossier["path"] == ~p"/games/#{game.id}/lobby"
    refute Map.has_key?(dossier, "case_content")
    refute Map.has_key?(dossier, "solution")
  end
end
