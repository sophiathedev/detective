defmodule DetectiveWeb.PageController do
  use DetectiveWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
