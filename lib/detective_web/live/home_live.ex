defmodule DetectiveWeb.HomeLive do
  use DetectiveWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Detective: City of Angels",
       signed_in: not is_nil(socket.assigns.current_scope)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.svelte
        id="home-frontend"
        name="Home"
        props={%{signed_in: @signed_in, locale: @locale}}
        socket={@socket}
      />
    </Layouts.app>
    """
  end
end
