defmodule Detective.Games.LobbyBroadcaster do
  @moduledoc false

  alias DetectiveWeb.Endpoint

  def broadcast_lobby(lobby) do
    public_lobby = Map.delete(lobby, :membership)

    Endpoint.broadcast(topic(lobby.id), "lobby_state", %{
      version: lobby.current_version,
      lobby: public_lobby
    })
  end

  defp topic(game_id), do: "lobby:#{game_id}"
end
