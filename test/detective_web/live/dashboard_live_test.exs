defmodule DetectiveWeb.DashboardLiveTest do
  use DetectiveWeb.ConnCase, async: true

  import Detective.AccountsFixtures
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
    refute Map.has_key?(component.props, "email")
  end
end
