defmodule DetectiveWeb.GameLive do
  use DetectiveWeb, :live_view

  alias Detective.Games

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    case Games.game_projection(socket.assigns.current_scope, game_id) do
      {:ok, projection} ->
        {:ok,
         assign(socket,
           page_title: "Casebook",
           game_id: game_id,
           projection: projection
         )}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "This casebook is unavailable.")
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.svelte
        id="game-book-frontend"
        name="GameBook"
        props={
          %{
            game_id: @game_id,
            user_id: @current_scope.user.id,
            initial_public: @projection.public,
            initial_private: @projection.private
          }
        }
        socket={@socket}
      />
    </Layouts.app>
    """
  end
end
