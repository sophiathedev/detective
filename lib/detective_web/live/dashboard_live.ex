defmodule DetectiveWeb.DashboardLive do
  use DetectiveWeb, :live_view

  alias Detective.Games

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       display_name: user.display_name,
       games: Games.game_summary(socket.assigns.current_scope)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.svelte
        id="dashboard-frontend"
        name="Dashboard"
        props={
          %{
            display_name: @display_name,
            games: @games
          }
        }
        socket={@socket}
      />
    </Layouts.app>
    """
  end
end
