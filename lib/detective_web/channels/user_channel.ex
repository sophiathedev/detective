defmodule DetectiveWeb.UserChannel do
  use DetectiveWeb, :channel

  alias Detective.Games
  alias Detective.Security.RateLimiter

  @sync_limit 10
  @rate_window_ms 2_000

  @impl true
  def join("user:" <> _scope = topic, %{"game_id" => game_id}, socket) do
    expected_topic = private_topic(socket.assigns.user_id, game_id)

    if topic == expected_topic do
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

  def join("user:" <> _scope, _payload, _socket),
    do: {:error, %{code: "invalid_command"}}

  @impl true
  def handle_in("sync_state", _payload, socket) do
    with :ok <- rate_limit(socket),
         {:ok, projection} <-
           Games.game_projection(socket.assigns.current_scope, socket.assigns.game_id) do
      {:reply,
       {:ok,
        %{
          game_id: projection.public.game_id,
          version: projection.public.version,
          state: projection.private
        }}, socket}
    else
      {:error, reason} -> {:reply, {:error, %{code: error_code(reason)}}, socket}
    end
  end

  def handle_in(_event, _payload, socket) do
    _result = rate_limit(socket)
    {:reply, {:error, %{code: "invalid_command"}}, socket}
  end

  defp rate_limit(socket) do
    RateLimiter.check(
      {:private_sync, socket.assigns.user_id, socket.assigns.game_id},
      limit: @sync_limit,
      window_ms: @rate_window_ms
    )
  end

  defp private_topic(user_id, game_id), do: "user:#{user_id}:game:#{game_id}"

  defp error_code(reason)
       when reason in [
              :invalid_game_id,
              :not_a_member,
              :game_not_active,
              :snapshot_not_found,
              :rate_limited
            ],
       do: Atom.to_string(reason)

  defp error_code(_reason), do: "unavailable"
end
