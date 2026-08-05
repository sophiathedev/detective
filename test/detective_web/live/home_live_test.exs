defmodule DetectiveWeb.HomeLiveTest do
  use DetectiveWeb.ConnCase

  import LiveSvelte.Test
  import Phoenix.LiveViewTest

  test "renders LiveSvelte as the primary frontend", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#app-shell.noir-app-shell")
    assert has_element?(view, "#home-frontend")

    component = get_svelte(view, id: "home-frontend")
    assert component.name == "Home"
    assert component.props["app_name"] == "Detective"
    assert component.props["count"] == 0
  end

  test "updates server state passed to Svelte", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "increment")
    assert get_svelte(view, id: "home-frontend").props["count"] == 1

    render_click(view, "decrement")
    assert get_svelte(view, id: "home-frontend").props["count"] == 0
  end
end
