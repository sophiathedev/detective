defmodule DetectiveWeb.PageControllerTest do
  use DetectiveWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Detective is ready for its frontend"
  end
end
