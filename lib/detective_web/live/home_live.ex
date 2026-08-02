defmodule DetectiveWeb.HomeLive do
  use DetectiveWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Home",
       count: 0,
       phoenix_version: to_string(Application.spec(:phoenix, :vsn)),
       live_svelte_version: to_string(Application.spec(:live_svelte, :vsn))
     )}
  end

  @impl true
  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("decrement", _params, socket) do
    {:noreply, update(socket, :count, &max(&1 - 1, 0))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <.svelte
        id="home-frontend"
        name="Home"
        props={
          %{
            app_name: "Detective",
            count: @count,
            phoenix_version: @phoenix_version,
            live_svelte_version: @live_svelte_version
          }
        }
        socket={@socket}
      />
    </Layouts.app>
    """
  end
end
