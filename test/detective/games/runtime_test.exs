defmodule Detective.Games.RuntimeTest do
  use Detective.DataCase, async: false

  import Detective.AccountsFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope

  alias Detective.Games.{
    Command,
    CommandRecord,
    Event,
    Game,
    GameEvent,
    GamePrivateEvent,
    GameSnapshot,
    Persistence,
    Session,
    SessionSupervisor,
    State
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

    assert {:ok,
            %{
              version: placed_version,
              duplicate: false,
              events: [%Event{delivery_id: delivery_id, version: placed_version}]
            }} =
             Session.execute(game.id, detective.id, place)

    assert placed_version == lobby.current_version + 1
    assert is_binary(delivery_id)
    assert Repo.aggregate(GameSnapshot, :count) == 2
    assert Repo.aggregate(GameEvent, :count) == 2

    assert {:ok,
            %{
              version: ^placed_version,
              duplicate: true,
              events: [%Event{delivery_id: ^delivery_id, version: ^placed_version}]
            }} =
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

  test "pending interrogation restores across Chisel and Detective decisions" do
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

    {:ok, %{version: interrogation_version}} =
      Session.execute(game.id, detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :interrogate,
        expected_version: placed_version,
        payload: %{
          "suspect_id" => "night-clerk",
          "topic_id" => "victim-file",
          "spend_leverage" => false
        }
      })

    assert Repo.aggregate(GamePrivateEvent, :count) == 1
    restart_session(game.id)

    assert {:ok, restored_question} = Session.get_state(game.id)
    assert restored_question.phase == :waiting_for_chisel
    assert restored_question.pending_action["suspect_id"] == "night-clerk"
    assert restored_question.pending_action["stage"] == "block_decision"

    {:ok, %{version: response_version}} =
      Session.execute(game.id, host.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :allow_question,
        expected_version: interrogation_version,
        payload: %{}
      })

    {:ok, %{version: decision_version}} =
      Session.execute(game.id, host.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :select_response,
        expected_version: response_version,
        payload: %{"response_id" => "clerk-a-misdirection-2"}
      })

    restart_session(game.id)

    assert {:ok, restored_decision} = Session.get_state(game.id)
    assert restored_decision.phase == :waiting_for_detective_decision
    assert restored_decision.pending_action["selected_response_type"] == "misdirection"

    assert {:ok, %{version: resolved_version}} =
             Session.execute(game.id, detective.id, %Command{
               command_id: Ecto.UUID.generate(),
               type: :challenge_response,
               expected_version: decision_version,
               payload: %{}
             })

    assert resolved_version == decision_version + 1
    assert {:ok, resolved} = Session.get_state(game.id)
    player = State.player_by_user_id(resolved, detective.id)
    assert resolved.phase == :detective_turn
    assert resolved.pending_action == nil
    assert hd(player.statements)["resolution"] == "challenge_succeeded"
  end

  test "disconnect pause persists the pending interrogation and is idempotent" do
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

    {:ok, %{version: _interrogation_version}} =
      Session.execute(game.id, detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :interrogate,
        expected_version: placed_version,
        payload: %{
          "suspect_id" => "night-clerk",
          "topic_id" => "victim-file",
          "spend_leverage" => false
        }
      })

    assert {:ok, before_pause} = Session.get_state(game.id)
    pending_action = before_pause.pending_action
    command_count = Repo.aggregate(CommandRecord, :count)
    event_count = Repo.aggregate(GameEvent, :count)
    snapshot_count = Repo.aggregate(GameSnapshot, :count)

    assert {:ok, %{version: paused_version, events: [event]}} =
             Session.pause_for_disconnect(game.id, [detective.id])

    assert event.type == :game_paused

    assert %Game{status: "paused", phase: "paused", current_version: ^paused_version} =
             Repo.get!(Game, game.id)

    assert Repo.aggregate(CommandRecord, :count) == command_count
    assert Repo.aggregate(GameEvent, :count) == event_count + 1
    assert Repo.aggregate(GameSnapshot, :count) == snapshot_count + 1
    assert Repo.get_by!(GameEvent, game_id: game.id, event_type: "game_paused").sequence > 0

    assert Enum.count(
             Repo.all(GameEvent),
             &(&1.game_id == game.id and &1.event_type == "game_paused")
           ) ==
             1

    assert Enum.count(
             Repo.all(GameSnapshot),
             &(&1.game_id == game.id and &1.version == paused_version)
           ) ==
             1

    restart_session(game.id)
    assert {:ok, restored} = Session.get_state(game.id)
    assert restored.paused_from_phase == :waiting_for_chisel
    assert restored.pending_action == pending_action

    assert {:ok, %{version: ^paused_version, events: []}} =
             Session.pause_for_disconnect(game.id, [detective.id])

    assert Repo.aggregate(CommandRecord, :count) == command_count
    assert Repo.aggregate(GameEvent, :count) == event_count + 1
    assert Repo.aggregate(GameSnapshot, :count) == snapshot_count + 1
  end

  test "a correct persisted accusation closes the game and restores its public result" do
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

    {:ok, %{version: searched_version}} =
      Session.execute(game.id, detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :search_location,
        expected_version: placed_version,
        payload: %{}
      })

    {:ok, %{version: next_day_version}} =
      Session.execute(game.id, detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :end_turn,
        expected_version: searched_version,
        payload: %{}
      })

    assert {:ok, %{version: finished_version, events: events}} =
             Session.execute(game.id, detective.id, %Command{
               command_id: Ecto.UUID.generate(),
               type: :accuse,
               expected_version: next_day_version,
               payload: %{
                 "suspect_id" => "night-clerk",
                 "weapon_id" => "sealed-ledger",
                 "motive_id" => "cover-up"
               }
             })

    assert Enum.map(events, & &1.type) == [:accusation_submitted, :game_finished]

    assert %Game{status: "finished", phase: "finished", current_version: ^finished_version} =
             Repo.get!(Game, game.id)

    restart_session(game.id)
    assert {:ok, restored} = Session.get_state(game.id)
    assert restored.status == :finished
    assert restored.phase == :finished
    assert restored.winner["player_id"] == State.player_by_user_id(restored, detective.id).id
  end

  test "game projection fails closed when the authoritative session is terminal" do
    %{host: host, game: game, version: version} = ready_game()

    assert {:ok, _result} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               version
             )

    {:ok, session_pid} = SessionSupervisor.ensure_session(game.id)

    :sys.replace_state(session_pid, fn state ->
      %{state | status: :finished, phase: :finished}
    end)

    assert {:error, :game_not_active} =
             Games.game_projection(Scope.for_user(host), game.id)
  end

  test "the multi-Detective Snitch phase persists, restores, and delivers the final response" do
    host = user_fixture()
    first = user_fixture()
    second = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)

    assert {:ok, _result} = Invitations.accept(Scope.for_user(first), token)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(second), token)

    assert {:ok, %{lobby: first_ready}} =
             Games.set_ready(Scope.for_user(first), game.id, 0, true)

    assert {:ok, %{lobby: both_ready}} =
             Games.set_ready(
               Scope.for_user(second),
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

    {:ok, %{lobby: lobby}} =
      Games.start_game(
        Scope.for_user(host),
        game.id,
        Ecto.UUID.generate(),
        both_ready.current_version
      )

    {:ok, %{version: placed_version}} =
      Session.execute(game.id, first.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :place,
        expected_version: lobby.current_version,
        payload: %{"location_id" => "central-precinct"}
      })

    {:ok, %{version: question_version}} =
      Session.execute(game.id, first.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :interrogate,
        expected_version: placed_version,
        payload: %{
          "suspect_id" => "night-clerk",
          "topic_id" => "victim-file",
          "spend_leverage" => false
        }
      })

    {:ok, %{version: snitch_window_version}} =
      Session.execute(game.id, host.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :allow_question,
        expected_version: question_version,
        payload: %{}
      })

    assert %Game{phase: "waiting_for_snitches"} = Repo.get!(Game, game.id)
    restart_session(game.id)
    assert {:ok, restored_window} = Session.get_state(game.id)
    assert restored_window.phase == :waiting_for_snitches

    {:ok, %{version: reveal_version}} =
      Session.execute(game.id, second.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :choose_snitch,
        expected_version: snitch_window_version,
        payload: %{}
      })

    second_player = State.player_by_user_id(restored_window, second.id)

    {:ok, %{version: response_version}} =
      Session.execute(game.id, host.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :resolve_snitches,
        expected_version: reveal_version,
        payload: %{"blocked_player_ids" => []}
      })

    {:ok, %{version: decision_version}} =
      Session.execute(game.id, host.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :select_response,
        expected_version: response_version,
        payload: %{"response_id" => "clerk-a-misdirection-1"}
      })

    assert {:ok, %{state: finished_question}} =
             Session.execute(game.id, first.id, %Command{
               command_id: Ecto.UUID.generate(),
               type: :accept_response,
               expected_version: decision_version,
               payload: %{}
             })

    snitch = Map.fetch!(finished_question.players, second_player.id)
    assert snitch.scratch == 2

    assert hd(snitch.statements)["response_text"] ==
             "The register was blank when I locked the archive."
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

  defp restart_session(game_id) do
    {:ok, pid} = SessionSupervisor.ensure_session(game_id)
    monitor = Process.monitor(pid)
    assert :ok = DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :shutdown}
  end
end
