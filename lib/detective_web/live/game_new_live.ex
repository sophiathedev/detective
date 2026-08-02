defmodule DetectiveWeb.GameNewLive do
  use DetectiveWeb, :live_view

  alias Detective.{Cases, Games}
  alias DetectiveWeb.CoreComponents

  @default_invite_hours "24"

  @impl true
  def mount(_params, _session, socket) do
    form =
      socket.assigns.current_scope
      |> Games.change_game(%{})
      |> to_form(as: :game)

    {:ok,
     assign(socket,
       page_title: "Create game",
       form: form,
       invite_hours: @default_invite_hours,
       case_options: case_options(Cases.list_published_versions()),
       global_error: nil,
       created_room: nil
     )}
  end

  @impl true
  def handle_event("validate", %{"game" => game_params}, socket) do
    form =
      socket.assigns.current_scope
      |> Games.change_game(game_params)
      |> Map.put(:action, :validate)
      |> to_form(as: :game)

    {:noreply,
     assign(socket,
       form: form,
       invite_hours: invite_hours(game_params),
       global_error: nil
     )}
  end

  def handle_event("save", %{"game" => game_params}, socket) do
    case Games.create_game(socket.assigns.current_scope, game_params) do
      {:ok, %{game: game, invite_token: invite_token}} ->
        {:noreply,
         assign(socket,
           created_room: %{
             lobby_path: ~p"/games/#{game.id}/lobby",
             invite_url: url(~p"/invites/#{invite_token}"),
             room_code: game.room_code
           },
           global_error: nil
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset, as: :game),
           invite_hours: invite_hours(game_params),
           global_error: nil
         )}

      {:error, :case_version_not_published} ->
        {:noreply,
         assign(socket,
           global_error: "That case is no longer available. Choose another published case."
         )}

      {:error, :invalid_invite_expiry} ->
        {:noreply,
         assign(socket,
           invite_hours: invite_hours(game_params),
           global_error: "Choose a valid invitation expiry."
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.svelte
        id="create-game-frontend"
        name="CreateGame"
        props={
          %{
            form: serialize_form(@form, @invite_hours),
            case_options: @case_options,
            global_error: @global_error,
            created_room: @created_room
          }
        }
        socket={@socket}
      />
    </Layouts.app>
    """
  end

  defp serialize_form(form, invite_hours) do
    %{
      fields: %{
        title: Phoenix.HTML.Form.input_value(form, :title) || "",
        case_version_id: Phoenix.HTML.Form.input_value(form, :case_version_id) || "",
        max_detectives: Phoenix.HTML.Form.input_value(form, :max_detectives) || "",
        invite_hours: invite_hours
      },
      errors: serialize_errors(form.errors)
    }
  end

  defp serialize_errors(errors) do
    Enum.reduce(errors, %{}, fn {field, error}, acc ->
      Map.update(acc, field, [CoreComponents.translate_error(error)], fn messages ->
        messages ++ [CoreComponents.translate_error(error)]
      end)
    end)
  end

  defp case_options(case_versions) do
    Enum.map(case_versions, fn version ->
      %{
        value: version.id,
        label: "#{version.case_file.title} (version #{version.version})",
        description: version.case_file.description
      }
    end)
  end

  defp invite_hours(params), do: Map.get(params, "invite_hours", @default_invite_hours)
end
