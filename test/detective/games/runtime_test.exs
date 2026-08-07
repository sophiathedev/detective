defmodule Detective.Games.RuntimeTest do
  use Detective.DataCase, async: false

  import Detective.AccountsFixtures
  import Detective.CasesFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope

  alias Detective.Games.{
    Command,
    CommandRecord,
    Event,
    Game,
    GameEvent,
    GamePlayer,
    GamePrivateEvent,
    GameSnapshot,
    Persistence,
    Session,
    SessionSupervisor,
    State
  }

  alias Detective.{Cases, Games, Invitations}

  test "starts a waiting game from an exact legacy published case version" do
    canonical_version = case_version_fixture()
    legacy_content = legacy_case_definition_fixture(canonical_version.content)

    {:ok, legacy_version} =
      Cases.create_version(canonical_version.case_file, %{
        version: 2,
        published_at: DateTime.utc_now(:second),
        content: legacy_content
      })

    selected = Cases.get_published_version(legacy_version.id)
    assert selected.content["locations"] == legacy_content["locations"]
    refute Map.has_key?(selected.content, "board_id")

    host = user_fixture()
    first = user_fixture()
    second = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host, %{case_version: selected})
    assert %Game{status: "waiting"} = Repo.get!(Game, game.id)

    on_exit(fn ->
      case Registry.lookup(Detective.GameRegistry, game.id) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(SessionSupervisor, pid)
        [] -> :ok
      end
    end)

    assert {:ok, _result} = Invitations.accept(Scope.for_user(first), token)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(second), token)

    assert {:ok, %{lobby: first_ready}} =
             Games.set_ready(Scope.for_user(first), game.id, 0, true)

    assert {:ok, %{lobby: ready}} =
             Games.set_ready(
               Scope.for_user(second),
               game.id,
               first_ready.current_version,
               true
             )

    assert {:ok, %{lobby: active}} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               ready.current_version
             )

    assert active.status == "active"
    assert {:ok, state} = Session.get_state(game.id)
    assert state.case_definition["board_id"] == "dcoa_classic"
    refute Map.has_key?(state.case_definition, "locations")
    assert State.player_by_user_id(state, first.id).location_id == nil
    assert state.suspects["night-clerk"].location_id == "51"
  end

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

    assert {:error, :command_id_conflict} =
             Games.start_game(Scope.for_user(host), game.id, command_id, version + 1)

    assert Repo.aggregate(GameSnapshot, :count) == 1
    assert Repo.aggregate(GameEvent, :count) == 1
  end

  test "Classic start requires at least two ready Detectives" do
    host = user_fixture()
    %{game: empty_game} = game_fixture(host)

    assert {:error, :not_enough_detectives} =
             Games.start_game(
               Scope.for_user(host),
               empty_game.id,
               Ecto.UUID.generate(),
               0
             )

    detective = user_fixture()
    %{game: one_detective_game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: lobby}} =
             Games.set_ready(Scope.for_user(detective), one_detective_game.id, 0, true)

    assert {:error, :not_enough_detectives} =
             Games.start_game(
               Scope.for_user(host),
               one_detective_game.id,
               Ecto.UUID.generate(),
               lobby.current_version
             )
  end

  test "Classic start requires every Detective to be ready" do
    host = user_fixture()
    ready_detective = user_fixture()
    unready_detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(ready_detective), token)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(unready_detective), token)

    assert {:ok, %{lobby: lobby}} =
             Games.set_ready(Scope.for_user(ready_detective), game.id, 0, true)

    assert {:error, :detectives_not_ready} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               lobby.current_version
             )
  end

  test "Classic start rejects more than four ready Detectives" do
    host = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host, %{max_detectives: 4})

    lobby =
      Enum.reduce(1..4, %{current_version: 0}, fn _seat, lobby ->
        detective = user_fixture()
        assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

        assert {:ok, %{lobby: ready_lobby}} =
                 Games.set_ready(
                   Scope.for_user(detective),
                   game.id,
                   lobby.current_version,
                   true
                 )

        ready_lobby
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

    assert {:error, :too_many_detectives} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               lobby.current_version
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
      payload: %{"location_id" => "51"}
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

    conflicting = %{place | payload: %{"location_id" => "82"}}
    assert {:error, :command_id_conflict} = Session.execute(game.id, detective.id, conflicting)

    {:ok, pid} = SessionSupervisor.ensure_session(game.id)
    monitor = Process.monitor(pid)
    assert :ok = DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :shutdown}

    assert {:ok, restored} = Session.get_state(game.id)
    assert restored.version == placed_version
    assert restored.players[restored.current_detective_id].location_id == "51"

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
        payload: %{"location_id" => "51"}
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
    %{
      host: host,
      detective: detective,
      second_detective: second_detective,
      game: game,
      version: version
    } = ready_game()

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
        payload: %{"location_id" => "51"}
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

    {:ok, %{version: snitch_window_version}} =
      Session.execute(game.id, host.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :allow_question,
        expected_version: interrogation_version,
        payload: %{}
      })

    {:ok, %{version: response_version}} =
      Session.execute(game.id, second_detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :decline_snitch,
        expected_version: snitch_window_version,
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

  test "a Detective bribe persists its public marker and private Case card" do
    %{
      host: host,
      detective: detective,
      second_detective: second_detective,
      game: game,
      version: version
    } = ready_game()

    {:ok, %{lobby: lobby}} =
      Games.start_game(
        Scope.for_user(host),
        game.id,
        Ecto.UUID.generate(),
        version
      )

    {:ok, %{version: first_placed}} =
      execute_session_command(game.id, detective.id, :place, lobby.current_version, %{
        "location_id" => "51"
      })

    {:ok, %{version: second_turn}} =
      execute_session_command(game.id, detective.id, :end_turn, first_placed)

    {:ok, %{version: second_placed}} =
      execute_session_command(game.id, second_detective.id, :place, second_turn, %{
        "location_id" => "51"
      })

    {:ok, %{version: searched}} =
      execute_session_command(game.id, second_detective.id, :search_location, second_placed)

    {:ok, %{version: first_next_turn}} =
      execute_session_command(game.id, second_detective.id, :end_turn, searched)

    assert {:ok, before_bribe} = Session.get_state(game.id)
    target = State.player_by_user_id(before_bribe, second_detective.id)

    assert {:ok, %{version: bribed_version}} =
             execute_session_command(
               game.id,
               detective.id,
               :bribe_detective,
               first_next_turn,
               %{
                 "detective_player_id" => target.id,
                 "case_card_id" => "sealed-ledger"
               }
             )

    event = Repo.get_by!(GameEvent, event_type: "detective_bribed")
    assert event.public_payload["case_card_code"] == "B"
    refute Jason.encode!(event.public_payload) =~ "Sealed Ledger"

    private_event =
      GamePrivateEvent
      |> Repo.all()
      |> Enum.find(&(&1.payload["type"] == "bribe_result"))

    assert private_event.recipient_user_id == detective.id
    assert private_event.payload["case_card"]["title"] == "Sealed Ledger"

    restart_session(game.id)
    assert {:ok, restored} = Session.get_state(game.id)
    assert restored.version == bribed_version

    actor = State.player_by_user_id(restored, detective.id)
    restored_target = State.player_by_user_id(restored, second_detective.id)
    assert actor.scratch == 2
    assert actor.actions_remaining == 4
    assert "sealed-ledger" in actor.knowledge
    assert restored_target.scratch == 7
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
        payload: %{"location_id" => "51"}
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
    %{
      host: host,
      detective: detective,
      second_detective: second_detective,
      game: game,
      version: version
    } = ready_game()

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
        payload: %{"location_id" => "51"}
      })

    {:ok, %{version: searched_version}} =
      Session.execute(game.id, detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :search_location,
        expected_version: placed_version,
        payload: %{}
      })

    {:ok, %{version: second_turn_version}} =
      Session.execute(game.id, detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :end_turn,
        expected_version: searched_version,
        payload: %{}
      })

    {:ok, %{version: second_placed_version}} =
      Session.execute(game.id, second_detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :place,
        expected_version: second_turn_version,
        payload: %{"location_id" => "84"}
      })

    {:ok, %{version: next_day_version}} =
      Session.execute(game.id, second_detective.id, %Command{
        command_id: Ecto.UUID.generate(),
        type: :end_turn,
        expected_version: second_placed_version,
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

    assert {:ok, %{public: public_result}} =
             Games.game_projection(Scope.for_user(detective), game.id)

    assert public_result.status == "finished"
    assert public_result.result.winner["player_id"] == restored.winner["player_id"]
    assert public_result.result.solution["suspect_name"] == "Night Clerk"
    assert public_result.result.solution["weapon_label"] == "Sealed Ledger"
    assert public_result.result.solution["motive_label"] == "Cover up the altered register"

    detective_debrief =
      Enum.find(public_result.result.detectives, &(&1.player_id == restored.winner["player_id"]))

    assert detective_debrief.won
    assert detective_debrief.solve_attempt["correct_count"] == 3
    assert detective_debrief.final_guess == nil
  end

  test "finished game projection remains available to a member" do
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
      %{
        state
        | status: :finished,
          phase: :finished,
          winner: %{"role" => "chisel", "reason" => "time_expired"}
      }
    end)

    assert {:ok, %{public: public_result, private: private_result}} =
             Games.game_projection(Scope.for_user(host), game.id)

    assert public_result.status == "finished"
    assert public_result.result.winner == %{"role" => "chisel", "reason" => "time_expired"}
    assert public_result.result.solution["suspect_name"] == "Night Clerk"
    assert private_result.role == "chisel"
  end

  test "game projection authorizes membership with one database query" do
    %{host: host, game: game, version: version} = ready_game()

    assert {:ok, _result} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               version
             )

    {:ok, session_pid} = SessionSupervisor.ensure_session(game.id)
    _state = :sys.get_state(session_pid)

    handler_id = {__MODULE__, :projection_query_count, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:detective, :repo, :query],
        fn _event, _measurements, _metadata, pid -> send(pid, :projection_repo_query) end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, projection} = Games.game_projection(Scope.for_user(host), game.id)
    assert projection.public.game_id == game.id
    assert_receive :projection_repo_query
    refute_receive :projection_repo_query

    outsider = user_fixture()

    assert {:error, :not_a_member} =
             Games.game_projection(Scope.for_user(outsider), game.id)
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
        payload: %{"location_id" => "51"}
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
    second_detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(second_detective), token)

    assert {:ok, %{lobby: first_ready}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    assert {:ok, %{lobby: lobby}} =
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

    %{
      host: host,
      detective: detective,
      detectives: [detective, second_detective],
      second_detective: second_detective,
      game: game,
      version: lobby.current_version
    }
  end

  defp restart_session(game_id) do
    {:ok, pid} = SessionSupervisor.ensure_session(game_id)
    monitor = Process.monitor(pid)
    assert :ok = DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :shutdown}
  end

  defp execute_session_command(game_id, user_id, type, version, payload \\ %{}) do
    Session.execute(game_id, user_id, %Command{
      command_id: Ecto.UUID.generate(),
      type: type,
      expected_version: version,
      payload: payload
    })
  end
end
