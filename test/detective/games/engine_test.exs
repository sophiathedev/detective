defmodule Detective.Games.EngineTest do
  use ExUnit.Case, async: true

  alias Detective.Games.{Command, Engine, Rules, State}

  test "initializes exact turn-order Scratch and leverage without a Chisel turn" do
    state = new_state()
    first = player(state, "detective-1")
    second = player(state, "detective-2")
    chisel = player(state, "chisel")

    assert first.scratch == 4
    assert second.scratch == 5
    assert first.actions_remaining == 4
    assert first.leverage_supply == 7
    assert chisel.leverage_by_detective[first.id] == 1
    assert chisel.leverage_by_detective[second.id] == 1
    refute Map.has_key?(chisel, :scratch)
    refute Map.has_key?(chisel, :actions_remaining)
    assert state.current_detective_id == first.id
  end

  test "first-turn placement is free and requires a Police Station" do
    state = new_state()

    assert {:error, :police_station_required} =
             apply_command(state, "detective-1", :place, %{"location_id" => "archive"})

    assert {:ok, placed, [event]} =
             apply_command(state, "detective-1", :place, %{
               "location_id" => "central-precinct"
             })

    detective = player(placed, "detective-1")
    assert detective.location_id == "central-precinct"
    assert detective.actions_remaining == 4
    assert placed.version == 1
    assert event.type == :detective_placed

    assert {:error, :already_placed} =
             apply_command(placed, "detective-1", :place, %{
               "location_id" => "central-precinct"
             })
  end

  test "one Move reaches any location in the current district and border locations bridge districts" do
    state = placed_state()

    assert {:ok, at_archive, _events} =
             apply_command(state, "detective-1", :move, %{"location_id" => "archive"})

    assert player(at_archive, "detective-1").actions_remaining == 3

    assert {:error, :destination_outside_district} =
             apply_command(at_archive, "detective-1", :move, %{"location_id" => "pier-club"})

    assert {:ok, at_border, _events} =
             apply_command(at_archive, "detective-1", :move, %{"location_id" => "canal-gate"})

    assert {:ok, at_pier, [event]} =
             apply_command(at_border, "detective-1", :move, %{"location_id" => "pier-club"})

    detective = player(at_pier, "detective-1")
    assert detective.location_id == "pier-club"
    assert detective.actions_remaining == 1
    assert event.public_payload.from_location_id == "canal-gate"
  end

  test "Analyze exchanges one action for one Scratch" do
    state = placed_state()
    before = player(state, "detective-1")

    assert {:ok, next_state, [event]} = apply_command(state, "detective-1", :analyze)
    after_player = player(next_state, "detective-1")

    assert after_player.actions_remaining == before.actions_remaining - 1
    assert after_player.scratch == before.scratch + 1
    assert event.public_payload == %{player_id: before.id, actions_remaining: 3}
    assert event.private_payloads[before.user_id] == %{scratch: 5}
  end

  test "Kickback works once per day at a Mob Joint and pays for every player including Chisel" do
    state = placed_state()

    assert {:error, :mob_joint_required} = apply_command(state, "detective-1", :kickback)

    {:ok, at_border, _events} =
      apply_command(state, "detective-1", :move, %{"location_id" => "canal-gate"})

    {:ok, at_pier, _events} =
      apply_command(at_border, "detective-1", :move, %{"location_id" => "pier-club"})

    before = player(at_pier, "detective-1")
    assert {:ok, paid, [event]} = apply_command(at_pier, "detective-1", :kickback)
    after_player = player(paid, "detective-1")

    assert after_player.scratch == before.scratch + 3
    assert after_player.kickback_day == 1
    assert event.private_payloads[before.user_id].payout == 3
    assert {:error, :kickback_already_used} = apply_command(paid, "detective-1", :kickback)
  end

  test "turn, role, and expected version are server-authoritative" do
    state = placed_state()

    assert {:error, :not_your_turn} = apply_command(state, "detective-2", :analyze)
    assert {:error, :wrong_role} = apply_command(state, "chisel", :analyze)

    stale_command = command(:analyze, state.version + 1, %{})
    assert {:error, :stale_version} = Engine.apply(state, user_id("detective-1"), stale_command)
  end

  test "ending each Detective turn advances the day and opens accusation when time expires" do
    state = placed_state()

    assert {:ok, second_turn, events} = apply_command(state, "detective-1", :end_turn)
    assert second_turn.current_detective_id == player(second_turn, "detective-2").id
    assert Enum.map(events, & &1.type) == [:turn_ended, :turn_started]

    {:ok, second_placed, _events} =
      apply_command(second_turn, "detective-2", :place, %{
        "location_id" => "harbor-precinct"
      })

    assert {:ok, day_two, events} = apply_command(second_placed, "detective-2", :end_turn)
    assert day_two.day == 2
    assert day_two.days_remaining == 1
    assert day_two.current_detective_id == player(day_two, "detective-1").id
    assert Enum.map(events, & &1.type) == [:turn_ended, :day_advanced, :turn_started]

    {:ok, final_second_turn, _events} = apply_command(day_two, "detective-1", :end_turn)
    assert {:ok, accusation, events} = apply_command(final_second_turn, "detective-2", :end_turn)
    assert accusation.phase == :accusation
    assert accusation.days_remaining == 0
    assert accusation.current_detective_id == nil
    assert Enum.map(events, & &1.type) == [:turn_ended, :accusation_opened]
  end

  test "available action projection exposes valid placement and movement choices only to active Detective" do
    state = new_state()
    assert Rules.available_actions(state, user_id("detective-1")) == ["place"]
    assert Rules.available_actions(state, user_id("detective-2")) == []
    assert Rules.available_actions(state, user_id("chisel")) == []

    state = placed_state()
    actions = Rules.available_actions(state, user_id("detective-1"))
    assert "move" in actions
    assert "analyze" in actions
    assert "end_turn" in actions
    refute "kickback" in actions
    assert "interrogate" in actions
  end

  test "interrogation is location-bound, costs one action, and exposes options only to Chisel" do
    state = placed_state()

    assert {:error, :invalid_suspect} =
             apply_command(state, "detective-1", :interrogate, %{
               "suspect_id" => "unknown",
               "topic_id" => "victim-file"
             })

    assert {:error, :topic_not_known} =
             apply_command(state, "detective-1", :interrogate, %{
               "suspect_id" => "night-clerk",
               "topic_id" => "sealed-ledger"
             })

    assert {:ok, awaiting_chisel, [event]} =
             apply_command(state, "detective-1", :interrogate, %{
               "suspect_id" => "night-clerk",
               "topic_id" => "victim-file"
             })

    assert awaiting_chisel.phase == :waiting_for_chisel
    assert awaiting_chisel.pending_action["type"] == "interrogation"
    assert player(awaiting_chisel, "detective-1").actions_remaining == 3
    assert event.type == :interrogation_started
    refute Map.has_key?(event.public_payload, :response_options)

    chisel_payload = event.private_payloads[user_id("chisel")]
    assert chisel_payload.type == "chisel_response_options"

    assert Enum.map(chisel_payload.response_options, & &1.type) == [
             "most_useful",
             "misdirection",
             "misdirection"
           ]

    assert {:error, :wrong_phase} = apply_command(awaiting_chisel, "detective-1", :move)

    assert {:error, :wrong_role} =
             apply_command(awaiting_chisel, "detective-1", :select_response, %{
               "response_id" => "response-1"
             })
  end

  test "successful challenge is resolved by the server and returns the most useful statement" do
    state = awaiting_chisel_state()

    assert {:ok, awaiting_decision, [published]} =
             apply_command(state, "chisel", :select_response, %{
               "response_id" => "response-1"
             })

    assert awaiting_decision.phase == :waiting_for_detective_decision
    assert published.type == :response_published
    refute Map.has_key?(published.public_payload, :response_text)

    assert published.private_payloads[user_id("detective-1")].response_text ==
             "I never worked the midnight desk."

    assert {:error, :not_interrogating_detective} =
             apply_command(awaiting_decision, "detective-2", :challenge_response)

    assert {:ok, resolved, [event]} =
             apply_command(awaiting_decision, "detective-1", :challenge_response)

    detective = player(resolved, "detective-1")
    chisel = player(resolved, "chisel")

    assert resolved.phase == :detective_turn
    assert resolved.pending_action == nil
    assert event.type == :challenge_succeeded
    assert event.public_payload.succeeded
    assert detective.leverage_supply == 6
    assert detective.leverage_on_suspects["night-clerk"] == 1
    assert chisel.leverage_by_detective[detective.id] == 1

    assert hd(detective.statements)["response_text"] ==
             "The victim signed the register shortly before midnight."

    assert hd(detective.statements)["resolution"] == "challenge_succeeded"
  end

  test "failed challenge transfers the staked marker to the Chisel" do
    state = awaiting_chisel_state()

    assert {:ok, awaiting_decision, _events} =
             apply_command(state, "chisel", :select_response, %{
               "response_id" => "response-0"
             })

    assert {:ok, resolved, [event]} =
             apply_command(awaiting_decision, "detective-1", :challenge_response)

    detective = player(resolved, "detective-1")
    chisel = player(resolved, "chisel")
    assert event.type == :challenge_failed
    refute event.public_payload.succeeded
    assert detective.leverage_supply == 6
    assert chisel.leverage_by_detective[detective.id] == 2
    assert detective.leverage_on_suspects == %{}
  end

  test "accepting a response resumes the turn without spending leverage" do
    state = awaiting_chisel_state()

    assert {:ok, awaiting_decision, _events} =
             apply_command(state, "chisel", :select_response, %{
               "response_id" => "response-2"
             })

    assert {:ok, resolved, [event]} =
             apply_command(awaiting_decision, "detective-1", :accept_response)

    detective = player(resolved, "detective-1")
    assert event.type == :response_accepted
    assert detective.leverage_supply == 7
    assert hd(detective.statements)["resolution"] == "accepted"
    assert hd(detective.statements)["response_text"] == "The desk sergeant forged the register."
  end

  test "rejects a case definition without a valid Police Station" do
    content =
      put_in(case_definition()["locations"], [
        location("archive", "Archive", "standard", ["central"], 0.2, 0.3)
      ])

    assert {:error, :invalid_initial_state} =
             Engine.new(game(), players(), content)
  end

  defp new_state do
    assert {:ok, %State{} = state} = Engine.new(game(), players(), case_definition())
    state
  end

  defp placed_state do
    state = new_state()

    assert {:ok, placed, _events} =
             apply_command(state, "detective-1", :place, %{
               "location_id" => "central-precinct"
             })

    placed
  end

  defp awaiting_chisel_state do
    state = placed_state()

    assert {:ok, awaiting_chisel, _events} =
             apply_command(state, "detective-1", :interrogate, %{
               "suspect_id" => "night-clerk",
               "topic_id" => "victim-file"
             })

    awaiting_chisel
  end

  defp apply_command(state, actor, type, payload \\ %{}) do
    Engine.apply(state, user_id(actor), command(type, state.version, payload))
  end

  defp command(type, expected_version, payload) do
    %Command{
      command_id: Ecto.UUID.generate(),
      type: type,
      expected_version: expected_version,
      payload: payload
    }
  end

  defp player(state, key) do
    Map.fetch!(state.players, player_id(key))
  end

  defp game do
    %{id: Ecto.UUID.generate(), case_version_id: Ecto.UUID.generate()}
  end

  defp players do
    [
      participant("chisel", "chisel", nil),
      participant("detective-1", "detective", 1),
      participant("detective-2", "detective", 2)
    ]
  end

  defp participant(key, role, seat) do
    %{
      id: player_id(key),
      user_id: user_id(key),
      display_name: String.replace(key, "-", " ") |> String.capitalize(),
      role: role,
      seat: seat
    }
  end

  defp player_id("chisel"), do: "10000000-0000-0000-0000-000000000001"
  defp player_id("detective-1"), do: "10000000-0000-0000-0000-000000000002"
  defp player_id("detective-2"), do: "10000000-0000-0000-0000-000000000003"

  defp user_id("chisel"), do: "20000000-0000-0000-0000-000000000001"
  defp user_id("detective-1"), do: "20000000-0000-0000-0000-000000000002"
  defp user_id("detective-2"), do: "20000000-0000-0000-0000-000000000003"

  defp case_definition do
    %{
      "max_days" => 2,
      "case_cards" => [
        %{
          "id" => "victim-file",
          "code" => "A",
          "title" => "Victim File",
          "type" => "victim",
          "initially_known" => true
        },
        %{
          "id" => "sealed-ledger",
          "code" => "B",
          "title" => "Sealed Ledger",
          "type" => "evidence",
          "initially_known" => false
        }
      ],
      "locations" => [
        location(
          "central-precinct",
          "Central Precinct",
          "police_station",
          ["central"],
          0.15,
          0.24
        ),
        location("archive", "City Archive", "standard", ["central"], 0.38, 0.31),
        location("canal-gate", "Canal Gate", "standard", ["central", "harbor"], 0.58, 0.5),
        location("harbor-precinct", "Harbor Precinct", "police_station", ["harbor"], 0.78, 0.65),
        location("pier-club", "Pier Club", "mob_joint", ["harbor"], 0.86, 0.73)
      ],
      "suspects" => [
        %{
          "id" => "night-clerk",
          "name" => "Night Clerk",
          "occupation" => "records clerk",
          "location_id" => "central-precinct"
        }
      ],
      "response_matrix" => %{
        "night-clerk" => %{
          "victim-file" => %{
            "most_useful" => "The victim signed the register shortly before midnight.",
            "misdirections" => [
              "I never worked the midnight desk.",
              "The desk sergeant forged the register."
            ]
          }
        }
      }
    }
  end

  defp location(id, name, type, district_ids, x, y) do
    %{
      "id" => id,
      "name" => name,
      "type" => type,
      "district_ids" => district_ids,
      "x" => x,
      "y" => y
    }
  end
end
