defmodule DetectiveWeb.HealthControllerTest do
  use DetectiveWeb.ConnCase, async: true

  test "GET /health/live reports process liveness", %{conn: conn} do
    conn = get(conn, ~p"/health/live")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /health/ready verifies the database connection", %{conn: conn} do
    conn = get(conn, ~p"/health/ready")
    assert json_response(conn, 200) == %{"status" => "ready"}
  end
end
