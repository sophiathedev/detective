defmodule DetectiveWeb.HealthController do
  use DetectiveWeb, :controller

  alias Detective.Repo

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: 2_000, pool_timeout: 2_000) do
      {:ok, _result} ->
        json(conn, %{status: "ready"})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "unavailable"})
    end
  end
end
