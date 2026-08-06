defmodule DetectiveWeb.LobbyChannelTest do
  use Detective.DataCase, async: false

  @endpoint DetectiveWeb.Endpoint

  import Detective.AccountsFixtures
  import Detective.CasesFixtures
  import Detective.GamesFixtures
  import Phoenix.ChannelTest

  alias Detective.Accounts
  alias Detective.Accounts.Scope
  alias Detective.Games
  alias Detective.Games.GamePlayer
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

  test "a Detective leaves through an authenticated versioned command" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: lobby}, socket} =
             detective
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert_push "presence_state", _presence

    ref = push(socket, "leave_lobby", %{"expected_version" => lobby.current_version})
    assert_reply ref, :ok, %{path: "/dashboard", version: 1}
    assert_broadcast "lobby_state", %{version: 1, lobby: next_lobby}
    refute Enum.any?(next_lobby.players, &(&1.id == lobby.membership.id))
    assert_broadcast "player_left", %{player_id: player_id, version: 1}
    assert player_id == lobby.membership.id
  end

  test "the Chisel removes a Detective and the departure is broadcast" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, %{player: player}} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: lobby}, socket} =
             host
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert_push "presence_state", _presence

    ref =
      push(socket, "remove_player", %{
        "player_id" => player.id,
        "expected_version" => lobby.current_version
      })

    assert_reply ref, :ok, %{version: 1}
    assert_broadcast "lobby_state", %{version: 1, lobby: next_lobby}
    refute Enum.any?(next_lobby.players, &(&1.id == player.id))
    assert_broadcast "player_removed", %{player_id: player_id, version: 1}
    assert player_id == player.id
  end

  test "the Chisel revokes and regenerates invitations without broadcasting raw tokens" do
    host = user_fixture()
    %{game: game} = game_fixture(host)

    assert {:ok, %{lobby: lobby}, socket} =
             host
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert_push "presence_state", _presence

    revoke_ref =
      push(socket, "revoke_invite", %{"expected_version" => lobby.current_version})

    assert_reply revoke_ref, :ok, %{version: 1}
    assert_broadcast "lobby_state", %{version: 1, lobby: revoked_lobby}
    assert revoked_lobby.invite.status == "revoked"
    refute Map.has_key?(revoked_lobby.invite, :token)
    refute Map.has_key?(revoked_lobby.invite, :token_hash)

    regenerate_ref =
      push(socket, "regenerate_invite", %{
        "expected_version" => 1,
        "invite_hours" => 6
      })

    assert_reply regenerate_ref, :ok, %{invite_path: invite_path, version: 2}
    assert invite_path =~ ~r{^/invites/[A-Za-z0-9_-]+$}
    assert_broadcast "lobby_state", %{version: 2, lobby: active_lobby}
    assert active_lobby.invite.status == "active"
    refute inspect(active_lobby) =~ invite_path
  end

  test "the Chisel updates lobby case and capacity through the canonical projection" do
    host = user_fixture()
    replacement_case = case_version_fixture()
    %{game: game} = game_fixture(host, %{max_detectives: 4})

    assert {:ok, %{lobby: lobby}, socket} =
             host
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert_push "presence_state", _presence

    ref =
      push(socket, "update_lobby_settings", %{
        "case_version_id" => replacement_case.id,
        "max_detectives" => 3,
        "expected_version" => lobby.current_version
      })

    assert_reply ref, :ok, %{version: 1}
    assert_broadcast "lobby_state", %{version: 1, lobby: next_lobby}
    assert next_lobby.case_version_id == replacement_case.id
    assert next_lobby.case_title == replacement_case.case_file.title
    assert next_lobby.max_detectives == 3
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
    assert_reply ref, :ok, %{path: path, version: ^started_version}, 500
    assert path == "/games/#{game.id}"

    assert_broadcast "game_started", %{
      game_id: game_id,
      path: ^path,
      version: ^started_version
    }

    assert game_id == game.id
  end

  test "start_game reports not enough Detectives" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: ready_lobby}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    assert {:ok, %{lobby: lobby}, socket} =
             host
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert lobby.current_version == ready_lobby.current_version
    assert_push "presence_state", _presence

    ref =
      push(socket, "start_game", %{
        "command_id" => Ecto.UUID.generate(),
        "expected_version" => lobby.current_version
      })

    assert_reply ref, :error, %{code: "not_enough_detectives"}
  end

  test "start_game reports too many Detectives" do
    host = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host, %{max_detectives: 4})

    ready_lobby =
      Enum.reduce(1..4, %{current_version: 0}, fn _seat, lobby ->
        detective = user_fixture()
        assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

        assert {:ok, %{lobby: next_lobby}} =
                 Games.set_ready(
                   Scope.for_user(detective),
                   game.id,
                   lobby.current_version,
                   true
                 )

        next_lobby
      end)

    extra_detective = user_fixture()

    Repo.insert!(
      GamePlayer.changeset(
        %GamePlayer{
          game_id: game.id,
          user_id: extra_detective.id,
          role: "detective",
          seat: 5,
          ready: true,
          status: "active",
          joined_at: DateTime.utc_now(:second)
        },
        %{}
      )
    )

    assert {:ok, %{lobby: lobby}, socket} =
             host
             |> authenticated_socket()
             |> subscribe_and_join("lobby:#{game.id}", %{})

    assert lobby.current_version == ready_lobby.current_version
    assert_push "presence_state", _presence

    ref =
      push(socket, "start_game", %{
        "command_id" => Ecto.UUID.generate(),
        "expected_version" => lobby.current_version
      })

    assert_reply ref, :error, %{code: "too_many_detectives"}
  end

  defp authenticated_socket(user) do
    token = Accounts.generate_user_session_token(user)

    {:ok, socket} =
      connect(UserSocket, %{}, connect_info: %{session: %{"user_token" => token}})

    socket
  end
end
