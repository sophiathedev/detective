defmodule DetectiveWeb.GameChannelTest do
  use Detective.DataCase, async: false

  @endpoint DetectiveWeb.Endpoint

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import Phoenix.ChannelTest

  alias Detective.Accounts
  alias Detective.Accounts.Scope
  alias Detective.Games.SessionSupervisor
  alias Detective.{Games, Invitations}
  alias DetectiveWeb.UserSocket

  setup do
    host = user_fixture()
    detective = user_fixture()
    outsider = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: ready_lobby}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    assert {:ok, %{lobby: active_lobby}} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               ready_lobby.current_version
             )

    on_exit(fn ->
      case Registry.lookup(Detective.GameRegistry, game.id) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(SessionSupervisor, pid)
        [] -> :ok
      end
    end)

    %{host: host, detective: detective, outsider: outsider, game: game, lobby: active_lobby}
  end

  test "member receives public game state and only their private projection", context do
    socket = authenticated_socket(context.detective)

    assert {:ok, %{state: public_state}, _game_socket} =
             subscribe_and_join(socket, "game:#{context.game.id}", %{})

    public_json = Jason.encode!(public_state)
    refute public_json =~ "solution"
    refute public_json =~ "response_matrix"
    refute public_json =~ "scratch"

    assert {:ok, private_reply, _user_socket} =
             subscribe_and_join(socket, "user:#{context.detective.id}", %{
               "game_id" => context.game.id
             })

    assert private_reply.state.role == "detective"
    assert private_reply.state.scratch == 4
    refute Jason.encode!(private_reply) =~ "solution"

    assert {:error, %{code: "unauthorized"}} =
             subscribe_and_join(socket, "user:#{context.host.id}", %{
               "game_id" => context.game.id
             })
  end

  test "outsider cannot join public or private game channels", context do
    socket = authenticated_socket(context.outsider)

    assert {:error, %{code: "not_a_member"}} =
             subscribe_and_join(socket, "game:#{context.game.id}", %{})

    assert {:error, %{code: "not_a_member"}} =
             subscribe_and_join(socket, "user:#{context.outsider.id}", %{
               "game_id" => context.game.id
             })
  end

  test "click-style placement command persists and broadcasts canonical projections", context do
    socket = authenticated_socket(context.detective)

    assert {:ok, %{state: public_state}, game_socket} =
             subscribe_and_join(socket, "game:#{context.game.id}", %{})

    assert {:ok, _private_reply, _user_socket} =
             subscribe_and_join(socket, "user:#{context.detective.id}", %{
               "game_id" => context.game.id
             })

    command_id = Ecto.UUID.generate()

    ref =
      push(game_socket, "command", %{
        "command_id" => command_id,
        "type" => "place",
        "expected_version" => public_state.version,
        "payload" => %{"location_id" => "central-precinct"}
      })

    assert_reply ref, :ok, %{version: accepted_version, duplicate: false}
    assert accepted_version == public_state.version + 1

    assert_broadcast "detective_placed", %{
      event_id: event_id,
      version: ^accepted_version,
      payload: %{location_id: "central-precinct"}
    }

    assert is_binary(event_id)

    assert_broadcast "game_state", %{version: ^accepted_version, state: next_public}
    detective_id = detective_player_id(context.lobby.players)
    placed_player = Enum.find(next_public.players, &(&1.id == detective_id))
    assert placed_player.location_id == "central-precinct"

    assert_broadcast "private_state", %{
      game_id: game_id,
      version: ^accepted_version,
      state: next_private
    }

    assert game_id == context.game.id
    assert next_private.available_actions |> Enum.member?("move")

    move_ref =
      push(game_socket, "command", %{
        "command_id" => Ecto.UUID.generate(),
        "type" => "move",
        "expected_version" => accepted_version,
        "payload" => %{"location_id" => "canal-gate"}
      })

    assert_reply move_ref, :ok, %{version: moved_version, duplicate: false}
    assert moved_version == accepted_version + 1

    assert_broadcast "player_moved", %{
      version: ^moved_version,
      payload: %{location_id: "canal-gate", actions_remaining: 3}
    }

    assert_broadcast "game_state", %{version: ^moved_version, state: moved_public}
    moved_player = Enum.find(moved_public.players, &(&1.id == detective_id))
    assert moved_player.location_id == "canal-gate"
    assert moved_player.actions_remaining == 3

    duplicate_ref =
      push(game_socket, "command", %{
        "command_id" => command_id,
        "type" => "place",
        "expected_version" => public_state.version,
        "payload" => %{"location_id" => "central-precinct"}
      })

    assert_reply duplicate_ref, :ok, %{version: ^accepted_version, duplicate: true}

    assert_broadcast "detective_placed", %{
      event_id: ^event_id,
      version: ^accepted_version,
      payload: %{"location_id" => "central-precinct"}
    }

    assert_broadcast "game_state", %{version: ^moved_version}
  end

  test "Chisel private topic receives the casebook but no fake action economy", context do
    socket = authenticated_socket(context.host)

    assert {:ok, reply, _user_socket} =
             subscribe_and_join(socket, "user:#{context.host.id}", %{
               "game_id" => context.game.id
             })

    assert reply.state.role == "chisel"
    assert Map.has_key?(reply.state.casebook, :solution)
    refute Map.has_key?(reply.state, :scratch)
    refute Map.has_key?(reply.state, :actions_remaining)
  end

  test "interrogation delivers ARC options privately and resolves a server-owned challenge",
       context do
    detective_socket = authenticated_socket(context.detective)
    host_socket = authenticated_socket(context.host)

    assert {:ok, %{state: public_state}, detective_game_socket} =
             subscribe_and_join(detective_socket, "game:#{context.game.id}", %{})

    assert {:ok, _detective_private, _detective_user_socket} =
             subscribe_and_join(detective_socket, "user:#{context.detective.id}", %{
               "game_id" => context.game.id
             })

    assert {:ok, _host_public, host_game_socket} =
             subscribe_and_join(host_socket, "game:#{context.game.id}", %{})

    assert {:ok, _host_private, _host_user_socket} =
             subscribe_and_join(host_socket, "user:#{context.host.id}", %{
               "game_id" => context.game.id
             })

    place_ref =
      push(detective_game_socket, "command", %{
        "command_id" => Ecto.UUID.generate(),
        "type" => "place",
        "expected_version" => public_state.version,
        "payload" => %{"location_id" => "central-precinct"}
      })

    assert_reply place_ref, :ok, %{version: placed_version}

    interrogation_ref =
      push(detective_game_socket, "command", %{
        "command_id" => Ecto.UUID.generate(),
        "type" => "interrogate",
        "expected_version" => placed_version,
        "payload" => %{
          "suspect_id" => "night-clerk",
          "topic_id" => "victim-file",
          "spend_leverage" => false
        }
      })

    assert_reply interrogation_ref, :ok, %{version: interrogation_version}

    assert_broadcast "interrogation_started", %{payload: interrogation_payload}
    refute Map.has_key?(interrogation_payload, :response_options)

    assert_broadcast "private_event", %{
      type: "interrogation_started",
      payload: %{type: "chisel_response_options", response_options: options}
    }

    assert length(options) == 3

    select_ref =
      push(host_game_socket, "command", %{
        "command_id" => Ecto.UUID.generate(),
        "type" => "select_response",
        "expected_version" => interrogation_version,
        "payload" => %{"response_id" => "clerk-a-misdirection-1"}
      })

    assert_reply select_ref, :ok, %{version: decision_version}
    assert_broadcast "response_published", %{payload: response_payload}
    refute Map.has_key?(response_payload, :response_text)
    refute Jason.encode!(response_payload) =~ "misdirection"

    assert_broadcast "private_event", %{
      type: "response_published",
      payload: %{
        type: "suspect_response",
        response_text: "The register was blank when I locked the archive."
      }
    }

    challenge_ref =
      push(detective_game_socket, "command", %{
        "command_id" => Ecto.UUID.generate(),
        "type" => "challenge_response",
        "expected_version" => decision_version,
        "payload" => %{}
      })

    assert_reply challenge_ref, :ok, %{version: resolved_version}
    assert_broadcast "challenge_succeeded", %{version: ^resolved_version}

    assert_broadcast "private_event", %{
      type: "challenge_succeeded",
      payload: %{
        type: "challenge_resolved",
        succeeded: true,
        final_response_text: "The victim signed the register shortly before midnight."
      }
    }

    assert_broadcast "game_state", %{version: ^resolved_version, state: resolved_public}
    assert resolved_public.phase == "detective_turn"
    assert resolved_public.pending_interrogation == nil
  end

  defp authenticated_socket(user) do
    token = Accounts.generate_user_session_token(user)

    {:ok, socket} =
      connect(UserSocket, %{}, connect_info: %{session: %{"user_token" => token}})

    socket
  end

  defp detective_player_id(players) do
    players
    |> Enum.find(&(&1.role == "detective"))
    |> Map.fetch!(:id)
  end
end
