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

  def broadcast_game_started(lobby) do
    Endpoint.broadcast(topic(lobby.id), "game_started", %{
      game_id: lobby.id,
      path: "/games/#{lobby.id}",
      version: lobby.current_version
    })
  end

  def broadcast_cancelled(game_id, version) do
    Endpoint.broadcast(topic(game_id), "lobby_cancelled", %{
      game_id: game_id,
      path: "/dashboard",
      version: version
    })
  end

  def broadcast_player_departure(lobby, event, player_id)
      when event in [:player_left, :player_removed] do
    Endpoint.broadcast(topic(lobby.id), Atom.to_string(event), %{
      player_id: player_id,
      version: lobby.current_version
    })
  end

  defp topic(game_id), do: "lobby:#{game_id}"
end
