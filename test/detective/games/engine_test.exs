defmodule Detective.Games.EngineTest do
  use ExUnit.Case, async: true

  alias Detective.Games.{Command, Engine, Rules, State}

  test "accepts exactly one Chisel and two to four Detectives" do
    cases = [
      {0, 1, {:error, :invalid_initial_state}},
      {1, 1, {:error, :invalid_initial_state}},
      {2, 1, :ok},
      {4, 1, :ok},
      {5, 1, {:error, :invalid_initial_state}},
      {2, 0, {:error, :invalid_initial_state}},
      {2, 2, {:error, :invalid_initial_state}}
    ]

    Enum.each(cases, fn {detective_count, chisel_count, expected} ->
      actual =
        case Engine.new(
               game(),
               players_for_counts(detective_count, chisel_count),
               case_definition()
             ) do
          {:ok, %State{}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      assert actual == expected
    end)
  end

  test "initializes runtime locations from the canonical board catalog" do
    assert {:ok, state} = Engine.new(game(), players(), case_definition())

    assert map_size(state.locations) == 100
    assert state.locations["51"].name == "L.A. Police Department Headquarters"
  end

  test "adapts an exact legacy fixture before initializing runtime state" do
    assert {:ok, state} = Engine.new(game(), players(), legacy_case_definition())

    assert state.case_definition["board_id"] == "dcoa_classic"
    refute Map.has_key?(state.case_definition, "locations")
    assert state.suspects["night-clerk"].location_id == "51"
    assert Map.has_key?(state.case_definition["search_results"]["locations"], "51")
    refute Map.has_key?(state.case_definition["search_results"]["locations"], "central-precinct")
  end

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
             apply_command(state, "detective-1", :place, %{"location_id" => "48"})

    assert {:ok, placed, [event]} =
             apply_command(state, "detective-1", :place, %{
               "location_id" => "51"
             })

    detective = player(placed, "detective-1")
    assert detective.location_id == "51"
    assert detective.actions_remaining == 4
    assert placed.version == 1
    assert event.type == :detective_placed

    assert {:error, :already_placed} =
             apply_command(placed, "detective-1", :place, %{
               "location_id" => "51"
             })
  end

  test "one Move reaches any location in the current district and border locations bridge districts" do
    state = placed_state()

    assert {:ok, at_archive, _events} =
             apply_command(state, "detective-1", :move, %{"location_id" => "48"})

    assert player(at_archive, "detective-1").actions_remaining == 3

    assert {:error, :destination_outside_district} =
             apply_command(at_archive, "detective-1", :move, %{"location_id" => "84"})

    assert {:ok, at_border, _events} =
             apply_command(at_archive, "detective-1", :move, %{"location_id" => "82"})

    assert {:ok, at_pier, [event]} =
             apply_command(at_border, "detective-1", :move, %{"location_id" => "96"})

    detective = player(at_pier, "detective-1")
    assert detective.location_id == "96"
    assert detective.actions_remaining == 1
    assert event.public_payload.from_location_id == "82"
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
      apply_command(state, "detective-1", :move, %{"location_id" => "82"})

    {:ok, at_pier, _events} =
      apply_command(at_border, "detective-1", :move, %{"location_id" => "96"})

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
        "location_id" => "84"
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

  test "searching a location costs one action while its result and evidence stay private" do
    state = placed_state()

    assert "search_location" in Rules.available_actions(state, user_id("detective-1"))

    assert {:ok, searched, [event]} =
             apply_command(state, "detective-1", :search_location)

    detective = player(searched, "detective-1")
    chisel = player(searched, "chisel")

    assert detective.actions_remaining == 3
    assert detective.knowledge == ["victim-file", "sealed-ledger"]
    assert detective.evidence == ["sealed-ledger"]
    assert hd(detective.search_notes)["text"] == "The ledger was hidden behind the duty roster."
    assert searched.archived_searches == ["location:51"]

    assert searched.taken_evidence["sealed-ledger"] == %{
             "player_id" => detective.id,
             "taken_day" => 1,
             "release_day" => nil
           }

    assert event.type == :location_searched
    assert event.public_payload.evidence_taken_count == 1
    refute Map.has_key?(event.public_payload, :taken_case_card_codes)
    refute Jason.encode!(event.public_payload) =~ "sealed-ledger"
    refute Jason.encode!(event.public_payload) =~ "ledger was hidden"

    assert event.private_payloads[detective.user_id].case_cards == [
             %{
               id: "sealed-ledger",
               code: "B",
               title: "Sealed Ledger",
               type: "evidence",
               description: "A ledger removed from the station records.",
               takeable: true,
               initially_known: false
             }
           ]

    refute Map.has_key?(event.private_payloads, chisel.user_id)

    assert {:error, :search_archived} =
             apply_command(searched, "detective-1", :search_location)
  end

  test "searching a suspect is location-bound and an Archive result locks the target" do
    state = placed_state()

    assert {:error, :invalid_suspect} =
             apply_command(state, "detective-1", :search_suspect, %{
               "suspect_id" => "unknown"
             })

    assert {:ok, searched, [event]} =
             apply_command(state, "detective-1", :search_suspect, %{
               "suspect_id" => "night-clerk"
             })

    assert event.type == :suspect_searched
    assert event.public_payload.target_id == "night-clerk"
    assert "suspect:night-clerk" in searched.archived_searches

    assert {:error, :search_archived} =
             apply_command(searched, "detective-1", :search_suspect, %{
               "suspect_id" => "night-clerk"
             })
  end

  test "taken evidence is submitted faceup exactly three Day advances later" do
    state =
      placed_state()
      |> Map.put(:days_remaining, 5)

    assert {:ok, searched, _events} =
             apply_command(state, "detective-1", :search_location)

    holder = player(searched, "detective-1")
    assert searched.taken_evidence["sealed-ledger"]["release_day"] == 4
    assert "sealed-ledger" in holder.evidence
    refute "sealed-ledger" in searched.public_case_card_ids

    {:ok, day_one_second, _events} = apply_command(searched, "detective-1", :end_turn)

    {:ok, day_two, events} =
      day_one_second
      |> place_second_detective()
      |> apply_command("detective-2", :end_turn)

    refute Enum.any?(events, &(&1.type == :evidence_submitted))

    {:ok, day_two_second, _events} = apply_command(day_two, "detective-1", :end_turn)
    {:ok, day_three, events} = apply_command(day_two_second, "detective-2", :end_turn)
    refute Enum.any?(events, &(&1.type == :evidence_submitted))

    {:ok, day_three_second, _events} = apply_command(day_three, "detective-1", :end_turn)
    {:ok, day_four, events} = apply_command(day_three_second, "detective-2", :end_turn)

    assert Enum.map(events, & &1.type) == [
             :turn_ended,
             :day_advanced,
             :evidence_submitted,
             :turn_started
           ]

    assert "sealed-ledger" in day_four.public_case_card_ids
    assert day_four.taken_evidence == %{}
    refute "sealed-ledger" in player(day_four, "detective-1").evidence
    assert "sealed-ledger" in player(day_four, "detective-2").knowledge
  end

  test "discovering a hidden suspect grants an immediate free question or decline" do
    hidden_case =
      case_definition()
      |> update_in(["suspects"], fn suspects ->
        [
          %{
            "id" => "dock-runner",
            "name" => "Dock Runner",
            "occupation" => "courier",
            "location_id" => "51",
            "initially_known" => false
          }
          | suspects
        ]
      end)
      |> put_in(
        ["response_matrix", "dock-runner"],
        %{
          "victim-file" => %{
            "most_useful" => "I carried the victim's parcel before midnight.",
            "misdirections" => ["I never saw the parcel."]
          }
        }
      )
      |> put_in(
        ["search_results", "locations", "51", "reveal_suspect_ids"],
        ["dock-runner"]
      )
      |> put_in(
        ["search_results", "suspects", "dock-runner"],
        search_result("The courier has no loose property.", true)
      )

    assert {:ok, initial} = Engine.new(game(), players(), hidden_case)

    {:ok, placed, _events} =
      apply_command(initial, "detective-1", :place, %{"location_id" => "51"})

    refute Map.fetch!(placed.suspects, "dock-runner").revealed

    assert {:ok, discovered, [event]} =
             apply_command(placed, "detective-1", :search_location)

    detective = player(discovered, "detective-1")
    assert Map.fetch!(discovered.suspects, "dock-runner").revealed
    assert detective.free_question_suspect_id == "dock-runner"
    assert event.public_payload.free_question_available

    assert Rules.available_actions(discovered, detective.user_id) == [
             "interrogate",
             "skip_free_question"
           ]

    assert {:error, :free_question_pending} =
             apply_command(discovered, "detective-1", :move, %{"location_id" => "48"})

    actions_before = detective.actions_remaining

    assert {:ok, asking, [question]} =
             apply_command(discovered, "detective-1", :interrogate, %{
               "suspect_id" => "dock-runner",
               "topic_id" => "victim-file"
             })

    assert player(asking, "detective-1").actions_remaining == actions_before
    assert asking.pending_action["free_question"]
    assert question.public_payload.free_question

    assert {:ok, initial_again} = Engine.new(game(), players(), hidden_case)

    {:ok, placed_again, _events} =
      apply_command(initial_again, "detective-1", :place, %{
        "location_id" => "51"
      })

    {:ok, discovered_again, _events} =
      apply_command(placed_again, "detective-1", :search_location)

    assert {:ok, declined, [decline]} =
             apply_command(discovered_again, "detective-1", :skip_free_question)

    assert player(declined, "detective-1").free_question_suspect_id == nil
    assert decline.type == :free_question_declined
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

  test "Chisel may block a question and the active Detective may pay two Scratch to proceed" do
    state = interrogation_open_state()
    detective_before = player(state, "detective-1")
    chisel_before = player(state, "chisel")

    assert Rules.available_actions(state, chisel_before.user_id) == [
             "block_question",
             "allow_question"
           ]

    assert {:ok, blocked, [event]} = apply_command(state, "chisel", :block_question)
    detective = player(blocked, "detective-1")
    chisel = player(blocked, "chisel")

    assert event.type == :question_blocked
    assert blocked.phase == :waiting_for_detective_decision
    assert blocked.pending_action["stage"] == "blocked_question"
    assert detective.actions_remaining == detective_before.actions_remaining
    assert detective.leverage_supply == detective_before.leverage_supply + 1

    assert chisel.leverage_by_detective[detective.id] ==
             chisel_before.leverage_by_detective[detective.id] - 1

    assert Rules.available_actions(blocked, detective.user_id) == [
             "bribe_goon",
             "accept_question_block"
           ]

    assert {:ok, bribed, [bribe]} = apply_command(blocked, "detective-1", :bribe_goon)
    assert bribe.type == :goon_bribed
    assert player(bribed, "detective-1").scratch == detective.scratch - 2
    assert bribed.phase == :waiting_for_snitches

    assert {:ok, blocked_again, _events} =
             interrogation_open_state()
             |> apply_command("chisel", :block_question)

    assert {:ok, abandoned, [abandon_event]} =
             apply_command(blocked_again, "detective-1", :accept_question_block)

    assert abandon_event.type == :question_abandoned
    assert abandoned.phase == :detective_turn
    assert abandoned.pending_action == nil
  end

  test "Snitch choice stays facedown, costs three Scratch only when allowed, and gets final response" do
    state = interrogation_open_state()

    assert {:ok, snitch_window, [allowed]} =
             apply_command(state, "chisel", :allow_question)

    assert allowed.type == :question_allowed
    assert snitch_window.phase == :waiting_for_snitches
    assert Rules.available_actions(snitch_window, user_id("detective-1")) == []

    assert Rules.available_actions(snitch_window, user_id("detective-2")) == [
             "choose_snitch",
             "decline_snitch"
           ]

    assert {:ok, awaiting_chisel, events} =
             apply_command(snitch_window, "detective-2", :choose_snitch)

    assert Enum.map(events, & &1.type) == [
             :snitch_decision_recorded,
             :snitch_window_closed
           ]

    assert awaiting_chisel.phase == :waiting_for_chisel
    assert awaiting_chisel.pending_action["stage"] == "snitch_block"
    assert Rules.available_actions(awaiting_chisel, user_id("chisel")) == ["resolve_snitches"]

    assert {:ok, response_stage, [resolved]} =
             apply_command(awaiting_chisel, "chisel", :resolve_snitches, %{
               "blocked_player_ids" => []
             })

    assert resolved.public_payload == %{
             interrogation_id: state.pending_action["id"],
             requested_count: 1,
             blocked_count: 0,
             allowed_count: 1
           }

    assert player(response_stage, "detective-2").scratch == 5

    {:ok, decision, _events} =
      apply_command(response_stage, "chisel", :select_response, %{
        "response_id" => "response-1"
      })

    assert {:ok, finished, [accepted]} =
             apply_command(decision, "detective-1", :accept_response)

    snitch = player(finished, "detective-2")
    assert snitch.scratch == 2
    assert hd(snitch.statements)["response_text"] == "I never worked the midnight desk."
    assert hd(snitch.statements)["resolution"] == "snitched"

    assert accepted.private_payloads[snitch.user_id] == %{
             type: "snitch_result",
             interrogation_id: state.pending_action["id"],
             response_text: "I never worked the midnight desk.",
             scratch: 2,
             scratch_spent: 3
           }
  end

  test "Chisel may spend matching leverage to block an individual Snitch" do
    state = interrogation_open_state()
    {:ok, snitch_window, _events} = apply_command(state, "chisel", :allow_question)

    {:ok, awaiting_chisel, _events} =
      apply_command(snitch_window, "detective-2", :choose_snitch)

    snitch_before = player(awaiting_chisel, "detective-2")

    assert {:ok, response_stage, [resolved]} =
             apply_command(awaiting_chisel, "chisel", :resolve_snitches, %{
               "blocked_player_ids" => [snitch_before.id]
             })

    snitch_after_block = player(response_stage, "detective-2")
    chisel_after_block = player(response_stage, "chisel")

    assert resolved.public_payload.blocked_count == 1
    assert snitch_after_block.leverage_supply == snitch_before.leverage_supply + 1
    assert chisel_after_block.leverage_by_detective[snitch_before.id] == 0

    {:ok, decision, _events} =
      apply_command(response_stage, "chisel", :select_response, %{
        "response_id" => "response-0"
      })

    {:ok, finished, [accepted]} = apply_command(decision, "detective-1", :accept_response)

    blocked_snitch = player(finished, "detective-2")
    assert blocked_snitch.scratch == snitch_before.scratch
    assert blocked_snitch.statements == []
    refute Map.has_key?(accepted.private_payloads, blocked_snitch.user_id)
  end

  test "Detective leverage forces the most useful response and closes the Snitch window" do
    state = placed_state()
    detective_id = player_id("detective-1")

    state =
      update_in(state.players[detective_id], fn detective ->
        %{
          detective
          | leverage_on_suspects: %{"night-clerk" => 1},
            leverage_supply: detective.leverage_supply - 1
        }
      end)

    assert {:ok, open, _events} =
             apply_command(state, "detective-1", :interrogate, %{
               "suspect_id" => "night-clerk",
               "topic_id" => "victim-file",
               "spend_leverage" => true
             })

    assert {:ok, response_stage, [event]} = apply_command(open, "chisel", :allow_question)
    refute event.public_payload.snitch_window_open
    assert response_stage.phase == :waiting_for_chisel
    assert response_stage.pending_action["stage"] == "response"

    assert {:error, :response_forced_truthful} =
             apply_command(response_stage, "chisel", :select_response, %{
               "response_id" => "response-1"
             })
  end

  test "a beginning-of-turn accusation consumes the Solve token and returns only a private count" do
    state = state_with_known_weapon()
    detective = player(state, "detective-1")
    assert "accuse" in Rules.available_actions(state, detective.user_id)

    assert {:ok, rejected, [event]} =
             apply_command(state, "detective-1", :accuse, %{
               "suspect_id" => "night-clerk",
               "weapon_id" => "sealed-ledger",
               "motive_id" => "robbery"
             })

    next_detective = player(rejected, "detective-1")
    refute next_detective.solve_token_available
    assert next_detective.actions_remaining == 4
    assert next_detective.solve_attempt["correct_count"] == 2
    assert rejected.phase == :detective_turn
    assert event.type == :accusation_rejected
    refute Map.has_key?(event.public_payload, :correct_count)
    refute Jason.encode!(event.public_payload) =~ "sealed-ledger"
    assert event.private_payloads[next_detective.user_id].correct_count == 2

    assert {:error, :solve_token_spent} =
             apply_command(rejected, "detective-1", :accuse, %{
               "suspect_id" => "night-clerk",
               "weapon_id" => "sealed-ledger",
               "motive_id" => "cover-up"
             })

    assert {:ok, analyzed, _events} = apply_command(state, "detective-1", :analyze)

    assert {:error, :accusation_must_start_turn} =
             apply_command(analyzed, "detective-1", :accuse, %{
               "suspect_id" => "night-clerk",
               "weapon_id" => "sealed-ledger",
               "motive_id" => "cover-up"
             })
  end

  test "a correct Solve accusation finishes the game and reveals the case result" do
    state = state_with_known_weapon()

    assert {:ok, finished, [submitted, result]} =
             apply_command(state, "detective-1", :accuse, %{
               "suspect_id" => "night-clerk",
               "weapon_id" => "sealed-ledger",
               "motive_id" => "cover-up"
             })

    assert submitted.type == :accusation_submitted
    assert result.type == :game_finished
    assert result.public_payload.solution["suspect_id"] == "night-clerk"
    assert finished.status == :finished
    assert finished.phase == :finished
    assert finished.current_detective_id == nil

    assert finished.winner == %{
             "role" => "detective",
             "player_id" => player_id("detective-1"),
             "reason" => "case_solved"
           }
  end

  test "final guesses stay private until all Detectives submit and ties resolve in reverse order" do
    state =
      state_with_known_weapon()
      |> put_known_weapon("detective-2")
      |> Map.put(:phase, :accusation)
      |> Map.put(:current_detective_id, nil)

    solution = %{
      "suspect_id" => "night-clerk",
      "weapon_id" => "sealed-ledger",
      "motive_id" => "cover-up"
    }

    assert {:ok, one_submitted, [first_event]} =
             apply_command(state, "detective-1", :submit_final_guess, solution)

    assert first_event.type == :final_guess_submitted
    refute Jason.encode!(first_event.public_payload) =~ "night-clerk"
    assert one_submitted.phase == :accusation
    assert player(one_submitted, "detective-1").final_guess == solution

    assert {:error, :final_guess_already_submitted} =
             apply_command(one_submitted, "detective-1", :submit_final_guess, solution)

    assert {:ok, finished, [second_event, result]} =
             apply_command(one_submitted, "detective-2", :submit_final_guess, solution)

    assert second_event.type == :final_guess_submitted
    assert result.type == :game_finished
    assert finished.status == :finished

    assert finished.winner == %{
             "role" => "detective",
             "player_id" => player_id("detective-2"),
             "reason" => "final_guess"
           }

    assert player(finished, "detective-1").final_guess["correct_count"] == 3
    assert player(finished, "detective-2").final_guess["correct_count"] == 3
  end

  test "Chisel wins after the final guesses when no Detective solves the case" do
    state =
      state_with_known_weapon()
      |> put_known_weapon("detective-2")
      |> Map.put(:phase, :accusation)
      |> Map.put(:current_detective_id, nil)

    wrong_guess = %{
      "suspect_id" => "night-clerk",
      "weapon_id" => "victim-file",
      "motive_id" => "robbery"
    }

    {:ok, one_submitted, _events} =
      apply_command(state, "detective-1", :submit_final_guess, wrong_guess)

    assert {:ok, finished, [_submitted, result]} =
             apply_command(one_submitted, "detective-2", :submit_final_guess, wrong_guess)

    assert result.public_payload.winner["role"] == "chisel"
    assert finished.winner["player_id"] == player_id("chisel")
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

  test "rejects a case definition with an unknown board" do
    content = Map.put(case_definition(), "board_id", "missing")

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
               "location_id" => "51"
             })

    placed
  end

  defp interrogation_open_state do
    state = placed_state()

    assert {:ok, awaiting_chisel, _events} =
             apply_command(state, "detective-1", :interrogate, %{
               "suspect_id" => "night-clerk",
               "topic_id" => "victim-file"
             })

    awaiting_chisel
  end

  defp awaiting_chisel_state do
    state = interrogation_open_state()

    assert {:ok, snitch_window, _events} = apply_command(state, "chisel", :allow_question)

    assert {:ok, awaiting_chisel, _events} =
             apply_command(snitch_window, "detective-2", :decline_snitch)

    awaiting_chisel
  end

  defp place_second_detective(state) do
    assert {:ok, placed, _events} =
             apply_command(state, "detective-2", :place, %{
               "location_id" => "84"
             })

    placed
  end

  defp state_with_known_weapon do
    placed_state()
    |> put_known_weapon("detective-1")
  end

  test "disconnect pause preserves and restores the exact phase" do
    state = awaiting_chisel_state()
    detective_id = player(state, "detective-1").id
    pending = state.pending_action

    assert {:error, :game_not_paused} = apply_command(state, "chisel", :resume_game)

    assert {:ok, paused, [pause_event]} =
             Engine.apply_system(state, {:pause_for_disconnect, [detective_id]})

    assert paused.status == :paused
    assert paused.phase == :paused
    assert paused.paused_from_phase == :waiting_for_chisel
    assert paused.pending_action == pending
    assert pause_event.type == :game_paused
    assert Rules.available_actions(paused, user_id("detective-1")) == []
    assert Rules.available_actions(paused, user_id("chisel")) == ["resume_game"]

    assert {:error, :game_paused} = apply_command(paused, "detective-1", :end_turn)
    assert {:error, :wrong_role} = apply_command(paused, "detective-1", :resume_game)

    assert {:ok, resumed, [resume_event]} = apply_command(paused, "chisel", :resume_game)

    assert resumed.status == :active
    assert resumed.phase == :waiting_for_chisel
    assert resumed.pending_action == pending
    assert resume_event.type == :game_resumed
  end

  test "resume restores every pausable gameplay phase" do
    phases = [
      :detective_turn,
      :waiting_for_chisel,
      :waiting_for_snitches,
      :waiting_for_detective_decision,
      :accusation
    ]

    Enum.each(phases, fn phase ->
      state = %{new_state() | phase: phase, pending_action: %{"saved_phase" => phase}}

      assert {:ok, paused, [_event]} =
               Engine.apply_system(
                 state,
                 {:pause_for_disconnect, [player(state, "detective-1").id]}
               )

      assert {:ok, resumed, [_event]} = apply_command(paused, "chisel", :resume_game)

      assert resumed.phase == phase
      assert resumed.pending_action == state.pending_action
    end)
  end

  defp put_known_weapon(state, detective_key) do
    detective_id = player_id(detective_key)

    update_in(state.players[detective_id], fn detective ->
      %{detective | knowledge: Enum.uniq(["sealed-ledger" | detective.knowledge])}
    end)
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

  defp players_for_counts(detective_count, chisel_count) do
    detectives =
      for seat <- 1..detective_count//1 do
        counted_participant("detective", seat, seat)
      end

    chisels =
      for index <- 1..chisel_count//1 do
        counted_participant("chisel", index, nil)
      end

    chisels ++ detectives
  end

  defp counted_participant(role, index, seat) do
    %{
      id: Ecto.UUID.generate(),
      user_id: Ecto.UUID.generate(),
      display_name: "#{role}-#{index}",
      role: role,
      seat: seat
    }
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
      "board_id" => "dcoa_classic",
      "case_cards" => [
        %{
          "id" => "victim-file",
          "code" => "A",
          "title" => "Victim File",
          "type" => "victim",
          "description" => "The victim's movements before midnight.",
          "initially_known" => true
        },
        %{
          "id" => "sealed-ledger",
          "code" => "B",
          "title" => "Sealed Ledger",
          "type" => "evidence",
          "description" => "A ledger removed from the station records.",
          "takeable" => true,
          "initially_known" => false
        }
      ],
      "suspects" => [
        %{
          "id" => "night-clerk",
          "name" => "Night Clerk",
          "occupation" => "records clerk",
          "location_id" => "51"
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
      },
      "accusation_options" => %{
        "weapons" => [
          %{
            "id" => "sealed-ledger",
            "label" => "Sealed Ledger",
            "case_card_id" => "sealed-ledger"
          },
          %{
            "id" => "victim-file",
            "label" => "Victim File",
            "case_card_id" => "victim-file"
          }
        ],
        "motives" => [
          %{"id" => "cover-up", "label" => "Cover up the forged register"},
          %{"id" => "robbery", "label" => "Robbery"}
        ]
      },
      "solution" => %{
        "suspect_id" => "night-clerk",
        "weapon_id" => "sealed-ledger",
        "motive_id" => "cover-up"
      },
      "epilogue" => "The clerk used the ledger to conceal the forged register.",
      "search_results" => %{
        "locations" => %{
          "51" =>
            search_result(
              "The ledger was hidden behind the duty roster.",
              true,
              ["sealed-ledger"],
              ["sealed-ledger"]
            )
        },
        "suspects" => %{
          "night-clerk" => search_result("The clerk carries only a brass pencil.", true)
        },
        "all_other_locations" =>
          search_result("A careful search uncovers nothing connected to the case.", false)
      }
    }
  end

  defp legacy_case_definition do
    case_definition()
    |> Map.delete("board_id")
    |> Map.put("locations", [
      legacy_location(
        "central-precinct",
        "Central Precinct",
        "police_station",
        ["central"],
        0.25,
        0.35
      ),
      legacy_location(
        "canal-gate",
        "Canal Gate",
        "standard",
        ["central", "harbor"],
        0.5,
        0.5
      ),
      legacy_location("pier-club", "Pier Club", "mob_joint", ["harbor"], 0.75, 0.7)
    ])
    |> put_in(["suspects", Access.at(0), "location_id"], "central-precinct")
    |> update_in(["search_results", "locations"], fn %{"51" => result} ->
      %{"central-precinct" => result}
    end)
  end

  defp legacy_location(id, name, type, district_ids, x, y) do
    %{
      "id" => id,
      "name" => name,
      "type" => type,
      "district_ids" => district_ids,
      "x" => x,
      "y" => y
    }
  end

  defp search_result(text, archive, reveal_card_ids \\ [], take_card_ids \\ []) do
    %{
      "text" => text,
      "archive" => archive,
      "reveal_case_card_ids" => reveal_card_ids,
      "take_case_card_ids" => take_card_ids,
      "reveal_suspect_ids" => []
    }
  end
end
