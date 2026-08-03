defmodule DetectiveWeb.InviteLive do
  use DetectiveWeb, :live_view

  alias Detective.Games
  alias Detective.Games.LobbyBroadcaster
  alias Detective.Invitations

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Invitations.preview(socket.assigns.current_scope, token) do
      {:ok, invite} ->
        {:ok,
         assign(socket,
           page_title: "Game invitation",
           invite: invite,
           invite_token: token,
           error: nil
         )}

      {:error, reason} ->
        {:ok,
         assign(socket,
           page_title: "Game invitation",
           invite: nil,
           invite_token: token,
           error: error_message(reason)
         )}
    end
  end

  @impl true
  def handle_event("accept_invite", _params, socket) do
    case Invitations.accept(socket.assigns.current_scope, socket.assigns.invite_token) do
      {:ok, %{game: game}} ->
        {:ok, lobby} = Games.get_lobby(socket.assigns.current_scope, game.id)
        :ok = LobbyBroadcaster.broadcast_lobby(lobby)

        {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}/lobby")}

      {:error, :already_a_member} when not is_nil(socket.assigns.invite) ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{socket.assigns.invite.game_id}/lobby")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.svelte
        id="invite-frontend"
        name="Invite"
        props={%{invite: @invite, error: @error}}
        socket={@socket}
      />
    </Layouts.app>
    """
  end

  defp error_message(reason)

  defp error_message(reason)
       when reason in [
              :invalid_invite,
              :invite_revoked,
              :invite_expired,
              :invite_exhausted,
              :game_not_waiting
            ],
       do: "This invitation is no longer available."

  defp error_message(:room_full), do: "This room is full."
  defp error_message(:removed_from_game), do: "You cannot join this room."
  defp error_message(_reason), do: "Unable to join this room."
end
