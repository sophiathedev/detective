defmodule Detective.Games.SnapshotCodecTest do
  use ExUnit.Case, async: true

  alias Detective.Games.{SnapshotCodec, State}

  test "round-trips authoritative state without exposing unsupported atoms" do
    player_id = Ecto.UUID.generate()
    user_id = Ecto.UUID.generate()

    state = %State{
      game_id: Ecto.UUID.generate(),
      case_version_id: Ecto.UUID.generate(),
      version: 7,
      day: 2,
      days_remaining: 4,
      chisel_player_id: Ecto.UUID.generate(),
      current_detective_id: player_id,
      detective_order: [player_id],
      players: %{
        player_id => %{
          id: player_id,
          user_id: user_id,
          display_name: "Ada",
          role: "detective",
          seat: 1,
          location_id: "51",
          actions_remaining: 3,
          scratch: 5,
          leverage_supply: 7,
          leverage_on_suspects: %{},
          knowledge: ["signal-log"],
          statements: [],
          search_notes: [
            %{
              "target_type" => "location",
              "target_id" => "51",
              "text" => "A private search result.",
              "case_card_ids" => ["signal-log"],
              "taken_case_card_ids" => ["signal-log"],
              "day" => 2
            }
          ],
          evidence: ["signal-log"],
          free_question_suspect_id: "witness",
          solve_token_available: false,
          solve_attempt: %{"suspect_id" => "witness"},
          final_guess: nil,
          kickback_day: nil
        }
      },
      locations: %{
        "51" => %{
          id: "51",
          name: "L.A. Police Department Headquarters",
          type: "police_station",
          district_ids: ["central_la"],
          x: 0.623,
          y: 0.5527
        }
      },
      special_actors: %{
        "station-tail" => %{
          id: "station-tail",
          name: "Station Tail",
          role: "counter-surveillance lookout",
          kind: "counter_surveillance",
          location_id: "51",
          visible: true,
          active: false,
          interaction_disabled: true,
          blocks: ["search_location"],
          options: [
            %{
              id: "buy-off",
              label: "Buy off the lookout",
              action_cost: 1,
              scratch_cost: 2,
              once: true,
              effects: [%{"type" => "disable_actor"}]
            }
          ],
          used_option_ids: ["buy-off"]
        }
      },
      case_definition: %{
        "solution" => %{"suspect_id" => "secret"},
        "published" => true
      },
      public_case_card_ids: ["public-log"],
      archived_searches: ["location:51"],
      taken_evidence: %{
        "signal-log" => %{
          "player_id" => player_id,
          "taken_day" => 2,
          "release_day" => 5
        }
      },
      triggered_special_rule_ids: ["late-witness"]
    }

    dumped = SnapshotCodec.dump(state)
    assert dumped["phase"] == "detective_turn"
    assert dumped["case_definition"]["published"] == true
    assert dumped["case_definition"]["solution"]["suspect_id"] == "secret"

    assert {:ok, restored} = SnapshotCodec.load(dumped)
    assert restored.game_id == state.game_id
    assert restored.phase == :detective_turn
    assert restored.version == 7
    assert restored.players[player_id].scratch == 5
    assert restored.players[player_id].evidence == ["signal-log"]
    assert restored.players[player_id].free_question_suspect_id == "witness"
    refute restored.players[player_id].solve_token_available
    assert restored.locations["51"].district_ids == ["central_la"]
    refute restored.special_actors["station-tail"].active
    assert restored.special_actors["station-tail"].visible
    assert restored.special_actors["station-tail"].interaction_disabled
    assert restored.special_actors["station-tail"].used_option_ids == ["buy-off"]
    assert restored.case_definition["solution"]["suspect_id"] == "secret"
    assert restored.public_case_card_ids == ["public-log"]
    assert restored.archived_searches == ["location:51"]
    assert restored.taken_evidence["signal-log"]["release_day"] == 5
    assert restored.triggered_special_rule_ids == ["late-witness"]
  end

  test "migrates schema version 3 snapshots without triggered special rules" do
    state = %State{players: %{}, locations: %{}, suspects: %{}}

    dumped =
      state
      |> SnapshotCodec.dump()
      |> Map.put("schema_version", 3)
      |> Map.delete("triggered_special_rule_ids")

    assert {:ok, restored} = SnapshotCodec.load(dumped)
    assert restored.triggered_special_rule_ids == []
  end

  test "migrates schema version 4 snapshots without special actors" do
    state = %State{players: %{}, locations: %{}, suspects: %{}}

    dumped =
      state
      |> SnapshotCodec.dump()
      |> Map.put("schema_version", 4)
      |> Map.delete("special_actors")

    assert {:ok, restored} = SnapshotCodec.load(dumped)
    assert restored.special_actors == %{}
  end

  test "migrates schema version 5 actors as visible" do
    state = %State{
      players: %{},
      locations: %{},
      suspects: %{},
      special_actors: %{
        "tail" => %{
          id: "tail",
          name: "Tail",
          role: "lookout",
          kind: "counter_surveillance",
          location_id: "51",
          visible: true,
          active: true,
          interaction_disabled: false,
          blocks: ["search_location"],
          options: [],
          used_option_ids: []
        }
      }
    }

    dumped =
      state
      |> SnapshotCodec.dump()
      |> Map.put("schema_version", 5)
      |> update_in(["special_actors", "tail"], fn actor ->
        Map.drop(actor, ["visible", "interaction_disabled"])
      end)

    assert {:ok, restored} = SnapshotCodec.load(dumped)
    assert restored.special_actors["tail"].visible
    refute restored.special_actors["tail"].interaction_disabled
  end

  test "round-trips a pending interrogation with string keys" do
    state = %State{
      game_id: Ecto.UUID.generate(),
      case_version_id: Ecto.UUID.generate(),
      version: 4,
      phase: :waiting_for_detective_decision,
      players: %{},
      locations: %{},
      suspects: %{},
      pending_action: %{
        "id" => Ecto.UUID.generate(),
        "type" => "interrogation",
        "detective_player_id" => Ecto.UUID.generate(),
        "detective_user_id" => Ecto.UUID.generate(),
        "suspect_id" => "night-clerk",
        "topic_id" => "victim-file",
        "topic_code" => "A",
        "forced_truthful" => false,
        "selected_response_id" => "response-1",
        "selected_response_text" => "A false trail.",
        "selected_response_type" => "misdirection"
      }
    }

    assert {:ok, restored} = state |> SnapshotCodec.dump() |> SnapshotCodec.load()
    assert restored.phase == :waiting_for_detective_decision
    assert restored.pending_action == state.pending_action
  end

  test "paused snapshots preserve prior phase and pending action" do
    state = %State{
      game_id: Ecto.UUID.generate(),
      case_version_id: Ecto.UUID.generate(),
      players: %{},
      locations: %{},
      suspects: %{}
    }

    paused = %{
      state
      | status: :paused,
        phase: :paused,
        paused_from_phase: :waiting_for_chisel,
        pause_reason: :player_disconnected,
        paused_player_ids: ["detective-player"],
        pending_action: %{"type" => "interrogation", "id" => "question-1"}
    }

    assert {:ok, restored} = paused |> SnapshotCodec.dump() |> SnapshotCodec.load()
    assert restored.paused_from_phase == :waiting_for_chisel
    assert restored.pause_reason == :player_disconnected
    assert restored.paused_player_ids == ["detective-player"]
    assert restored.pending_action == paused.pending_action
  end

  test "schema two snapshots load with empty pause metadata" do
    legacy =
      %State{players: %{}, locations: %{}, suspects: %{}}
      |> SnapshotCodec.dump()
      |> Map.put("schema_version", 2)
      |> Map.drop(["paused_from_phase", "pause_reason", "paused_player_ids"])

    assert {:ok, restored} = SnapshotCodec.load(legacy)
    assert restored.paused_from_phase == nil
    assert restored.pause_reason == nil
    assert restored.paused_player_ids == []
  end

  test "rejects an unsupported snapshot schema" do
    assert {:error, :unsupported_snapshot} =
             SnapshotCodec.load(%{"schema_version" => State.schema_version() + 1})
  end
end
