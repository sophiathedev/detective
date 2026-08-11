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

           row
           |> Map.put(:path, path)
           |> maybe_put_replay_path()
         end)}
      end)

    {:ok,
     assign(socket,
       page_title: gettext("Dashboard"),
       display_name: user.display_name,
       games: Games.game_summary(socket.assigns.current_scope),
       dossiers: game_dossiers,
       rematch_room: nil,
       rematch_error: nil
     )}
  end

  @impl true
  def handle_event("rematch", %{"id" => game_id}, socket) do
    case Games.rematch(socket.assigns.current_scope, game_id) do
      {:ok, %{game: game} = result} ->
        invite_token = result.invite_token

        {:noreply,
         assign(socket,
           rematch_room: %{
             path: game_path(game),
             invite_url: invite_token && url(~p"/invites/#{invite_token}"),
             room_code: game.room_code,
             duplicate: result.duplicate
           },
           rematch_error: nil
         )}

      {:error, :not_rematchable} ->
        {:noreply,
         assign(socket,
           rematch_error: gettext("Only the Chisel can reopen a closed case."),
           rematch_room: nil
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           rematch_error: gettext("The rematch room could not be created."),
           rematch_room: nil
         )}
    end
  end

  def handle_event("dismiss_rematch", _params, socket) do
    {:noreply, assign(socket, rematch_room: nil, rematch_error: nil)}
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
            rematch_room: @rematch_room,
            rematch_error: @rematch_error,
            locale: @locale
          }
        }
        socket={@socket}
      />
    </Layouts.app>
    """
  end

  defp game_path(%{status: "waiting", id: id}), do: ~p"/games/#{id}/lobby"
  defp game_path(%{id: id}), do: ~p"/games/#{id}"

  defp maybe_put_replay_path(%{status: "finished", id: id} = row),
    do: Map.put(row, :replay_path, ~p"/games/#{id}/replay")

  defp maybe_put_replay_path(row), do: row
end
