defmodule DetectiveWeb.DashboardLive do
  use DetectiveWeb, :live_view

  alias Detective.Games

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    game_dossiers =
      socket.assigns.current_scope
      |> Games.list_game_dossiers()
      |> Map.new(fn {bucket, rows} ->
        {bucket,
         Enum.map(rows, fn row ->
           path =
             if row.status == "waiting",
               do: ~p"/games/#{row.id}/lobby",
               else: ~p"/games/#{row.id}"

           Map.put(row, :path, path)
         end)}
      end)

    {:ok,
     assign(socket,
       page_title: gettext("Dashboard"),
       display_name: user.display_name,
       games: Games.game_summary(socket.assigns.current_scope),
       dossiers: game_dossiers
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
            games: @games,
            dossiers: @dossiers,
            locale: @locale
          }
        }
        socket={@socket}
      />
    </Layouts.app>
    """
  end
end
