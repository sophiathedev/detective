defmodule Detective.Games.RuntimeTest do
  use Detective.DataCase, async: false

  import Detective.AccountsFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope

  alias Detective.Games.{
    Command,
    CommandRecord,
    Game,
    GameEvent,
    GamePrivateEvent,
    GameSnapshot,
    Persistence,
    Session,
    SessionSupervisor
  }

  alias Detective.{Games, Invitations}

  test "start validates readiness and persists one recoverable initial state" do
    %{host: host, detective: detective, game: game, version: version} = ready_game()
    command_id = Ecto.UUID.generate()

    assert {:ok, %{event: :game_started, duplicate: false, lobby: lobby}} =
             Games.start_game(Scope.for_user(host), game.id, command_id, version)

    assert lobby.status == "active"
    assert lobby.phase == "detective_turn"
    assert lobby.current_version == version + 1

    assert %Game{status: "active", phase: "detective_turn"} = Repo.get!(Game, game.id)
    assert Repo.aggregate(GameSnapshot, :count) == 1
    assert Repo.aggregate(GameEvent, :count) == 1
    assert Repo.aggregate(CommandRecord, :count) == 1

    assert {:ok, state} = Session.get_state(game.id)
    assert state.version == version + 1
    assert state.current_detective_id != nil
    assert state.players[state.current_detective_id].user_id == detective.id

    assert {:ok, %{duplicate: true}} =
             Games.start_game(Scope.for_user(host), game.id, command_id, version)

    assert Repo.aggregate(GameSnapshot, :count) == 1
    assert Repo.aggregate(GameEvent, :count) == 1
  end

  test "start rejects missing and unready Detectives" do
    host = user_fixture()
    %{game: empty_game} = game_fixture(host)

    assert {:error, :no_detectives} =
             Games.start_game(
               Scope.for_user(host),
               empty_game.id,
               Ecto.UUID.generate(),
               0
             )

    detective = user_fixture()
    %{game: unready_game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:error, :detectives_not_ready} =
             Games.start_game(
               Scope.for_user(host),
               unready_game.id,
               Ecto.UUID.generate(),
               0
             )
  end

  test "GameSession serializes, persists, deduplicates, and restores commands" do
    %{host: host, detective: detective, game: game, version: version} = ready_game()

    assert {:ok, %{lobby: lobby}} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               version
             )

    command_id = Ecto.UUID.generate()

    place = %Command{
      command_id: command_id,
      type: :place,
      expected_version: lobby.current_version,
      payload: %{"location_id" => "central-precinct"}
    }

    assert {:ok, %{version: placed_version, duplicate: false}} =
             Session.execute(game.id, detective.id, place)

    assert placed_version == lobby.current_version + 1
    assert Repo.aggregate(GameSnapshot, :count) == 2
    assert Repo.aggregate(GameEvent, :count) == 2

    assert {:ok, %{version: ^placed_version, duplicate: true}} =
             Session.execute(game.id, detective.id, place)

    assert Repo.aggregate(GameSnapshot, :count) == 2
    assert Repo.aggregate(GameEvent, :count) == 2

    conflicting = %{place | payload: %{"location_id" => "canal-gate"}}
    assert {:error, :command_id_conflict} = Session.execute(game.id, detective.id, conflicting)

    {:ok, pid} = SessionSupervisor.ensure_session(game.id)
    monitor = Process.monitor(pid)
    assert :ok = DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :shutdown}

    assert {:ok, restored} = Session.get_state(game.id)
    assert restored.version == placed_version
    assert restored.players[restored.current_detective_id].location_id == "central-precinct"

    assert {:ok, loaded} = Persistence.load_state(game.id)
    assert loaded.version == placed_version
  end

  test "private event payload is persisted separately from the public event" do
    %{host: host, detective: detective, game: game, version: version} = ready_game()

    {:ok, %{lobby: lobby}} =
      Games.start_game(
        Scope.for_user(host),
        game.id,
        Ecto.UUID.generate(),
        version
      )

    {:ok, %{version: placed_version}} =
      Session.execute(game.id, detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :place,
        expected_version: lobby.current_version,
        payload: %{"location_id" => "central-precinct"}
      })

    assert {:ok, %{version: analyzed_version}} =
             Session.execute(game.id, detective.id, %Command{
               command_id: Ecto.UUID.generate(),
               type: :analyze,
               expected_version: placed_version,
               payload: %{}
             })

    assert analyzed_version == placed_version + 1
    assert Repo.aggregate(GamePrivateEvent, :count) == 1

    private_event = Repo.one!(GamePrivateEvent)
    assert private_event.recipient_user_id == detective.id
    assert private_event.payload == %{"scratch" => 5}

    analyzed_event = Repo.get_by!(GameEvent, event_type: "evidence_analyzed")
    refute Map.has_key?(analyzed_event.public_payload, "scratch")
  end

  defp ready_game do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: lobby}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    on_exit(fn ->
      case Registry.lookup(Detective.GameRegistry, game.id) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(SessionSupervisor, pid)
        [] -> :ok
      end
    end)

    %{host: host, detective: detective, game: game, version: lobby.current_version}
  end
end
