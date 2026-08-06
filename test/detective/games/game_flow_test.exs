defmodule Detective.Games.GameFlowTest do
  use Detective.DataCase, async: false

  import Detective.AccountsFixtures
  import Detective.CasesFixtures
  import Detective.GamesFixtures
  import Ecto.Query

  alias Detective.Accounts.Scope

  alias Detective.Games.{
    Command,
    Game,
    GameEvent,
    GamePrivateEvent,
    GameSnapshot,
    Session,
    SessionSupervisor,
    State
  }

  alias Detective.{Cases, Games, Invitations}

  test "plays a persisted game from special contact through solved accusation" do
    %{
      host: host,
      detective: detective,
      second_detective: second_detective,
      game: game,
      lobby_version: lobby_version
    } = ready_branching_game()

    assert {:ok, %{lobby: lobby}} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               lobby_version
             )

    placed =
      execute(game.id, detective.id, :place, lobby.current_version, %{
        "location_id" => "51"
      })

    assert {:ok, contact_projection} =
             Games.game_projection(Scope.for_user(detective), game.id)

    assert [contact] = contact_projection.private.special_actor_interactions
    assert contact.actor_id == "station-tail"
    assert Enum.map(contact.options, & &1.id) == ["buy-off", "shadow-tail"]
    refute Jason.encode!(contact_projection.private) =~ "disable_actor"
    refute Jason.encode!(contact_projection.private) =~ "public_case_cards"

    interacted =
      execute(game.id, detective.id, :interact_special_actor, placed.version, %{
        "actor_id" => "station-tail",
        "option_id" => "buy-off"
      })

    assert [%{type: :special_actor_interacted} = interaction_event] = interacted.events
    refute interaction_event.public_payload.actor_active
    refute Jason.encode!(interaction_event.public_payload) =~ "disable_actor"

    assert interacted.state.special_actors["station-tail"].resolved_choice_groups == [
             "tail-approach"
           ]

    searched = execute(game.id, detective.id, :search_location, interacted.version)

    assert [%{type: :location_searched} = search_event] = searched.events
    refute Jason.encode!(search_event.public_payload) =~ "sealed-ledger"

    questioned =
      execute(game.id, detective.id, :interrogate, searched.version, %{
        "suspect_id" => "night-clerk",
        "topic_id" => "victim-file",
        "spend_leverage" => false
      })

    allowed = execute(game.id, host.id, :allow_question, questioned.version)
    declined = execute(game.id, second_detective.id, :decline_snitch, allowed.version)

    answered =
      execute(game.id, host.id, :select_response, declined.version, %{
        "response_id" => "clerk-a-misdirection-1"
      })

    challenged = execute(game.id, detective.id, :challenge_response, answered.version)
    assert [%{type: :challenge_succeeded}] = challenged.events

    detective_state = State.player_by_user_id(challenged.state, detective.id)
    assert hd(detective_state.statements)["resolution"] == "challenge_succeeded"
    assert "sealed-ledger" in detective_state.knowledge

    moved =
      execute(game.id, detective.id, :move, challenged.version, %{"location_id" => "82"})

    assert [%{type: :player_moved, public_payload: movement}] = moved.events
    assert movement.from_location_id == "51"
    assert movement.location_id == "82"

    first_turn_ended = execute(game.id, detective.id, :end_turn, moved.version)

    second_placed =
      execute(game.id, second_detective.id, :place, first_turn_ended.version, %{
        "location_id" => "84"
      })

    next_day = execute(game.id, second_detective.id, :end_turn, second_placed.version)
    assert next_day.state.day == 2
    assert State.player_by_user_id(next_day.state, detective.id).actions_remaining == 4

    solved =
      execute(game.id, detective.id, :accuse, next_day.version, %{
        "suspect_id" => "night-clerk",
        "weapon_id" => "sealed-ledger",
        "motive_id" => "cover-up"
      })

    assert Enum.map(solved.events, & &1.type) == [:accusation_submitted, :game_finished]
    assert solved.state.status == :finished
    assert solved.state.winner["role"] == "detective"

    assert %Game{
             status: "finished",
             phase: "finished",
             current_version: finished_version
           } = Repo.get!(Game, game.id)

    assert finished_version == solved.version

    assert_public_event_order(game.id)
    assert_response_secrecy(game.id, detective.id)
    assert_latest_snapshot(game.id, solved.version)

    restart_session(game.id)
    assert {:ok, restored} = Session.get_state(game.id)
    assert restored.version == solved.version
    assert restored.status == :finished
    assert restored.players[restored.winner["player_id"]].user_id == detective.id
    refute restored.special_actors["station-tail"].active
    assert restored.special_actors["station-tail"].resolved_choice_groups == ["tail-approach"]
  end

  defp ready_branching_game do
    base_version = case_version_fixture()

    content =
      Map.put(base_version.content, "special_actors", [
        %{
          "id" => "station-tail",
          "name" => "Station Tail",
          "role" => "counter-surveillance lookout",
          "kind" => "counter_surveillance",
          "location_id" => "51",
          "blocks" => ["search_location", "search_suspect", "interrogate"],
          "options" => [
            %{
              "id" => "buy-off",
              "label" => "Buy off the lookout",
              "action_cost" => 1,
              "scratch_cost" => 2,
              "once" => true,
              "choice_group" => "tail-approach",
              "effects" => [%{"type" => "disable_actor"}]
            },
            %{
              "id" => "shadow-tail",
              "label" => "Shadow the lookout",
              "action_cost" => 2,
              "scratch_cost" => 0,
              "once" => true,
              "choice_group" => "tail-approach",
              "effects" => [
                %{"type" => "move_actor", "location_id" => "96"},
                %{
                  "type" => "public_case_cards",
                  "case_card_ids" => ["sealed-ledger"]
                }
              ]
            }
          ]
        }
      ])

    {:ok, case_version} =
      Cases.create_version(base_version.case_file, %{
        version: 2,
        content: content,
        published_at: DateTime.utc_now(:second)
      })

    host = user_fixture()
    detective = user_fixture()
    second_detective = user_fixture()

    %{game: game, invite_token: token} =
      game_fixture(host, %{case_version: case_version})

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

    on_exit(fn -> stop_session(game.id) end)

    %{
      host: host,
      detective: detective,
      second_detective: second_detective,
      game: game,
      lobby_version: ready_lobby.current_version
    }
  end

  defp execute(game_id, user_id, type, version, payload \\ %{}) do
    assert {:ok, result} =
             Session.execute(game_id, user_id, %Command{
               command_id: Ecto.UUID.generate(),
               type: type,
               expected_version: version,
               payload: payload
             })

    result
  end

  defp assert_public_event_order(game_id) do
    event_types =
      Repo.all(
        from event in GameEvent,
          where: event.game_id == ^game_id,
          order_by: event.sequence,
          select: event.event_type
      )

    core_flow = [
      "game_started",
      "detective_placed",
      "special_actor_interacted",
      "location_searched",
      "interrogation_started",
      "question_allowed",
      "snitch_decision_recorded",
      "response_published",
      "challenge_succeeded",
      "player_moved",
      "detective_placed",
      "day_advanced",
      "accusation_submitted",
      "game_finished"
    ]

    assert Enum.filter(event_types, &(&1 in core_flow)) == core_flow
  end

  defp assert_response_secrecy(game_id, detective_user_id) do
    response_event =
      Repo.one!(
        from event in GameEvent,
          where: event.game_id == ^game_id and event.event_type == "response_published"
      )

    refute Jason.encode!(response_event.public_payload) =~ "misdirection"
    refute Jason.encode!(response_event.public_payload) =~ "register was blank"

    private_event =
      Repo.get_by!(GamePrivateEvent,
        game_event_id: response_event.id,
        recipient_user_id: detective_user_id
      )

    assert private_event.payload["response_text"] ==
             "The register was blank when I locked the archive."
  end

  defp assert_latest_snapshot(game_id, version) do
    snapshot = Repo.get_by!(GameSnapshot, game_id: game_id, version: version)
    assert snapshot.schema_version == State.schema_version()
    assert snapshot.state_json["status"] == "finished"
  end

  defp restart_session(game_id) do
    stop_session(game_id)
    assert {:ok, _pid} = SessionSupervisor.ensure_session(game_id)
  end

  defp stop_session(game_id) do
    case Registry.lookup(Detective.GameRegistry, game_id) do
      [{pid, _value}] ->
        monitor = Process.monitor(pid)
        assert :ok = DynamicSupervisor.terminate_child(SessionSupervisor, pid)
        assert_receive {:DOWN, ^monitor, :process, ^pid, :shutdown}

      [] ->
        :ok
    end
  end
end
