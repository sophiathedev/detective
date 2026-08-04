defmodule DetectiveWeb.LobbyChannelTest do
  use Detective.DataCase, async: false

  @endpoint DetectiveWeb.Endpoint

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import Phoenix.ChannelTest

  alias Detective.Accounts
  alias Detective.Accounts.Scope
  alias Detective.Games
  alias Detective.Games.SessionSupervisor
  alias Detective.Invitations
  alias DetectiveWeb.UserSocket

  test "active member joins and receives allow-listed lobby and presence" do
    host = user_fixture()
    %{game: game} = game_fixture(host)
    socket = authenticated_socket(host)

    assert {:ok, %{lobby: lobby}, _socket} =
             subscribe_and_join(socket, "lobby:#{game.id}", %{})

    assert lobby.id == game.id
    assert lobby.membership.role == "chisel"
    assert lobby.current_version == 0
    refute Map.has_key?(lobby, :content)
    refute Map.has_key?(lobby, :token_hash)
    assert_push "presence_state", presence
    assert Map.has_key?(presence, lobby.membership.id)
  end

  test "outsider and malformed game id are rejected" do
    host = user_fixture()
    outsider = user_fixture()
    %{game: game} = game_fixture(host)
    socket = authenticated_socket(outsider)

    assert {:error, %{code: "not_a_member"}} =
             subscribe_and_join(socket, "lobby:#{game.id}", %{})

    assert {:error, %{code: "invalid_game_id"}} =
             subscribe_and_join(socket, "lobby:not-a-uuid", %{})
  end

  test "detective readiness broadcasts a canonical versioned projection" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: lobby}, socket} =
             detective
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert_push "presence_state", _presence

    ref = push(socket, "ready", %{"expected_version" => lobby.current_version})
    assert_reply ref, :ok, %{version: 1}
    assert_broadcast "lobby_state", %{version: 1, lobby: broadcast_lobby}

    ready_player = Enum.find(broadcast_lobby.players, &(&1.id == lobby.membership.id))
    assert ready_player.ready
    refute Map.has_key?(broadcast_lobby, :membership)
    refute Map.has_key?(broadcast_lobby, :content)
  end

  test "Chisel cannot send a Detective readiness command" do
    host = user_fixture()
    %{game: game} = game_fixture(host)

    assert {:ok, %{lobby: lobby}, socket} =
             host
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert_push "presence_state", _presence

    ref = push(socket, "ready", %{"expected_version" => lobby.current_version})
    assert_reply ref, :error, %{code: "not_detective"}
    refute_broadcast "lobby_state", _payload
  end

  test "ready lobby starts once and broadcasts the game route" do
    host = user_fixture()
    detective = user_fixture()
    second_detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(second_detective), token)

    assert {:ok, %{lobby: first_ready}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    assert {:ok, %{lobby: ready_lobby}} =
             Games.set_ready(
               Scope.for_user(second_detective),
               game.id,
               first_ready.current_version,
               true
             )

    on_exit(fn ->
      case Registry.lookup(Detective.GameRegistry, game.id) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(SessionSupervisor, pid)
        [] -> :ok
      end
    end)

    assert {:ok, %{lobby: lobby}, socket} =
             host
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert lobby.current_version == ready_lobby.current_version
    assert_push "presence_state", _presence

    command_id = Ecto.UUID.generate()

    ref =
      push(socket, "start_game", %{
        "command_id" => command_id,
        "expected_version" => lobby.current_version
      })

    started_version = ready_lobby.current_version + 1
    assert_reply ref, :ok, %{path: path, version: ^started_version}
    assert path == "/games/#{game.id}"

    assert_broadcast "game_started", %{
      game_id: game_id,
      path: ^path,
      version: ^started_version
    }

    assert game_id == game.id
  end

  defp authenticated_socket(user) do
    token = Accounts.generate_user_session_token(user)

    {:ok, socket} =
      connect(UserSocket, %{}, connect_info: %{session: %{"user_token" => token}})

    socket
  end
end
