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
          location_id: "precinct",
          actions_remaining: 3,
          scratch: 5,
          leverage_supply: 7,
          leverage_on_suspects: %{},
          knowledge: ["signal-log"],
          kickback_day: nil
        }
      },
      locations: %{
        "precinct" => %{
          id: "precinct",
          name: "Precinct",
          type: "police_station",
          district_ids: ["central"],
          x: 0.2,
          y: 0.3
        }
      },
      case_definition: %{
        "solution" => %{"suspect_id" => "secret"},
        "published" => true
      }
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
    assert restored.locations["precinct"].district_ids == ["central"]
    assert restored.case_definition["solution"]["suspect_id"] == "secret"
  end

  test "rejects an unsupported snapshot schema" do
    assert {:error, :unsupported_snapshot} =
             SnapshotCodec.load(%{"schema_version" => State.schema_version() + 1})
  end
end
