defmodule DetectiveWeb.UserChannel do
  use DetectiveWeb, :channel

  alias Detective.Games

  @impl true
  def join("user:" <> user_id, %{"game_id" => game_id}, socket) do
    if user_id == socket.assigns.user_id do
      case Games.game_projection(socket.assigns.current_scope, game_id) do
        {:ok, projection} ->
          {:ok,
           %{
             game_id: projection.public.game_id,
             version: projection.public.version,
             state: projection.private
           }, assign(socket, :game_id, projection.public.game_id)}

        {:error, reason} ->
          {:error, %{code: error_code(reason)}}
      end
    else
      {:error, %{code: "unauthorized"}}
    end
  end

  def join("user:" <> _user_id, _payload, _socket),
    do: {:error, %{code: "invalid_command"}}

  @impl true
  def handle_in("sync_state", _payload, socket) do
    case Games.game_projection(socket.assigns.current_scope, socket.assigns.game_id) do
      {:ok, projection} ->
        {:reply,
         {:ok,
          %{
            game_id: projection.public.game_id,
            version: projection.public.version,
            state: projection.private
          }}, socket}

      {:error, reason} ->
        {:reply, {:error, %{code: error_code(reason)}}, socket}
    end
  end

  defp error_code(reason)
       when reason in [
              :invalid_game_id,
              :not_a_member,
              :game_not_active,
              :snapshot_not_found
            ],
       do: Atom.to_string(reason)

  defp error_code(_reason), do: "unavailable"
end
