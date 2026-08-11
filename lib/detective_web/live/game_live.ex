defmodule DetectiveWeb.GameLive do
  use DetectiveWeb, :live_view

  alias Detective.Games

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    with {:ok, projection} <- Games.game_projection(socket.assigns.current_scope, game_id),
         {:ok, note} <- Games.get_player_note(socket.assigns.current_scope, game_id) do
      {:ok,
       assign(socket,
         page_title: gettext("Casebook"),
         game_id: game_id,
         csrf_token: Plug.CSRFProtection.get_csrf_token(),
         projection: projection,
         note_form: to_form(%{"content" => note.content}, as: :note),
         note_saved: false,
         note_error: nil
       )}
    else
      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This casebook is unavailable."))
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("save_note", %{"note" => %{"content" => content}}, socket) do
    case Games.save_player_note(socket.assigns.current_scope, socket.assigns.game_id, content) do
      {:ok, note} ->
        {:noreply,
         assign(socket,
           note_form: to_form(%{"content" => note.content}, as: :note),
           note_saved: true,
           note_error: nil
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           note_form: to_form(changeset, as: :note),
           note_saved: false,
           note_error: gettext("Keep personal notes under 5000 characters.")
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           note_saved: false,
           note_error: gettext("The private note could not be saved.")
         )}
    end
  end

  def handle_event("save_note", _params, socket) do
    {:noreply,
     assign(socket,
       note_saved: false,
       note_error: gettext("The private note could not be saved.")
     )}
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
            initial_private: @projection.private,
            personal_note: %{
              content: Phoenix.HTML.Form.input_value(@note_form, :content) || "",
              saved: @note_saved,
              error: @note_error
            },
            csrf_token: @csrf_token,
            locale: @locale,
            return_path: ~p"/games/#{@game_id}"
          }
        }
        socket={@socket}
      />
    </Layouts.app>
    """
  end
end
