defmodule DetectiveWeb.UserSocket do
  use Phoenix.Socket, max_channels_per_transport: 8

  alias Detective.Accounts
  alias Detective.Accounts.Scope
  alias DetectiveWeb.UserAuth

  channel "lobby:*", DetectiveWeb.LobbyChannel
  channel "game:*", DetectiveWeb.GameChannel
  channel "user:*", DetectiveWeb.UserChannel

  @impl true
  def connect(_params, socket, %{session: %{"user_token" => token}}) do
    case Accounts.get_user_by_session_token(token) do
      {user, _inserted_at} ->
        {:ok,
         socket
         |> assign(:current_scope, Scope.for_user(user))
         |> assign(:user_id, user.id)
         |> assign(:session_topic, UserAuth.session_topic(token))}

      nil ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(%Phoenix.Socket{assigns: %{session_topic: session_topic}}), do: session_topic
  def id(_socket), do: nil
end
