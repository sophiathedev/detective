defmodule DetectiveWeb.LobbyLive do
  use DetectiveWeb, :live_view

  alias Detective.{Cases, Games}

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    case Games.get_lobby(socket.assigns.current_scope, game_id) do
      {:ok, lobby} ->
        {:ok,
         assign(socket,
           page_title: lobby.title,
           lobby: lobby,
           case_options: case_options(Cases.list_published_versions())
         )}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This room is unavailable."))
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.svelte
        id="lobby-frontend"
        name="Lobby"
        props={%{lobby: @lobby, case_options: @case_options, locale: @locale}}
        socket={@socket}
      />
    </Layouts.app>
    """
  end

  defp case_options(case_versions) do
    Enum.map(case_versions, fn version ->
      %{
        value: version.id,
        label:
          gettext("%{title} (version %{version})",
            title: version.case_file.title,
            version: version.version
          )
      }
    end)
  end
end
