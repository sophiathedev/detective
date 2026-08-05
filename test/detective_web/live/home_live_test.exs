defmodule DetectiveWeb.HomeLiveTest do
  use DetectiveWeb.ConnCase

  import Detective.AccountsFixtures
  import LiveSvelte.Test
  import Phoenix.LiveViewTest

  test "renders the public LiveSvelte case desk", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#app-shell.noir-app-shell")
    assert has_element?(view, "#home-frontend")

    component = get_svelte(view, id: "home-frontend")
    assert component.name == "Home"
    refute component.props["signed_in"]
  end

  test "projects signed-in state without user details", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/")

    component = get_svelte(view, id: "home-frontend")
    assert component.props["signed_in"]
    refute Map.has_key?(component.props, "email")
  end
end
