defmodule Detective.Cases.ValidatorTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.{ResponseMatrix, SpecialRules, Validator}

  test "validates an exact pre-catalog published fixture through the legacy adapter" do
    legacy = %{
      "locations" => legacy_fixture_locations(),
      "suspects" => [%{"id" => "suspect", "location_id" => "central-precinct"}]
    }

    assert :ok = Validator.validate(legacy)
  end

  test "rejects a raw canonical suspect reference on an exact legacy topology" do
    legacy = %{
      "locations" => legacy_fixture_locations(),
      "suspects" => [%{"id" => "suspect", "location_id" => "51"}]
    }

    assert {:error, :invalid_suspect_location} = Validator.validate(legacy)
  end

  test "rejects raw canonical and mixed Search references on an exact legacy topology" do
    Enum.each(
      [
        %{"51" => search_result([], [])},
        %{
          "central-precinct" => search_result([], []),
          "51" => search_result([], [])
        }
      ],
      fn search_locations ->
        legacy = %{
          "locations" => legacy_fixture_locations(),
          "suspects" => [%{"id" => "suspect", "location_id" => "central-precinct"}],
          "search_results" => %{"locations" => search_locations}
        }

        assert {:error, :invalid_search_results} = Validator.validate(legacy)
      end
    )
  end

  test "requires a known board and validates suspect/search location references" do
    content =
      valid_case()
      |> Map.delete("locations")
      |> put_in(["suspects", Access.at(0), "location_id"], "51")

    assert {:error, :unknown_board} = Validator.validate(Map.put(content, "board_id", "missing"))
    assert :ok = Validator.validate(Map.put(content, "board_id", "dcoa_classic"))

    invalid_suspect = put_in(content, ["suspects", Access.at(0), "location_id"], "101")

    assert {:error, :invalid_suspect_location} =
             Validator.validate(Map.put(invalid_suspect, "board_id", "dcoa_classic"))
  end

  test "accepts canonical board locations that keep every location within three Move actions" do
    assert :ok = Validator.validate(valid_case())
  end

  test "validates response references and requires one most useful response" do
    case_definition =
      valid_case()
      |> Map.put("case_cards", [
        %{
          "id" => "victim",
          "code" => "A",
          "title" => "Victim",
          "type" => "victim",
          "initially_known" => true
        },
        %{
          "id" => "receipt",
          "code" => "B",
          "title" => "Receipt",
          "type" => "evidence",
          "initially_known" => false
        }
      ])
      |> Map.put("response_matrix", %{
        "suspect" => %{
          "victim" => %{
            "most_useful" => %{
              "text" => "A useful answer.",
              "reveal_case_card_ids" => ["receipt"]
            },
            "misdirections" => ["A false trail."]
          }
        }
      })

    assert :ok = Validator.validate(case_definition)

    assert {:ok, [most_useful, misdirection]} =
             ResponseMatrix.response_options(case_definition, "suspect", "victim")

    assert most_useful.case_card_ids == ["receipt"]
    assert misdirection.case_card_ids == []

    invalid_reference = put_in(case_definition["response_matrix"]["unknown"], %{})
    assert {:error, :invalid_response_reference} = Validator.validate(invalid_reference)

    without_truth =
      put_in(
        case_definition["response_matrix"]["suspect"]["victim"]["most_useful"],
        ""
      )

    assert {:error, :invalid_response_matrix} = Validator.validate(without_truth)

    unknown_response_card =
      put_in(
        case_definition["response_matrix"]["suspect"]["victim"]["most_useful"][
          "reveal_case_card_ids"
        ],
        ["missing"]
      )

    assert {:error, :invalid_response_reference} = Validator.validate(unknown_response_card)

    duplicate_response_card =
      put_in(
        case_definition["response_matrix"]["suspect"]["victim"]["most_useful"][
          "reveal_case_card_ids"
        ],
        ["receipt", "receipt"]
      )

    assert {:error, :invalid_response_matrix} = Validator.validate(duplicate_response_card)
  end

  test "limits Case cards to A-L and accepts only local artwork assets" do
    card = %{
      "id" => "victim",
      "code" => "A",
      "title" => "Victim",
      "type" => "victim",
      "artwork_url" => "/images/cards/dcoa/faces/female-business.webp",
      "initially_known" => true
    }

    definition = %{"case_cards" => [card], "suspects" => [], "response_matrix" => %{}}

    assert :ok = ResponseMatrix.validate(definition)

    assert [%{artwork_url: "/images/cards/dcoa/faces/female-business.webp"}] =
             ResponseMatrix.topics(definition)

    invalid_code = put_in(definition, ["case_cards", Access.at(0), "code"], "M")
    assert {:error, :invalid_case_cards} = ResponseMatrix.validate(invalid_code)

    remote_artwork =
      put_in(
        definition,
        ["case_cards", Access.at(0), "artwork_url"],
        "https://tracker.example/card.png"
      )

    assert {:error, :invalid_case_cards} = ResponseMatrix.validate(remote_artwork)

    traversal_artwork =
      put_in(definition, ["case_cards", Access.at(0), "artwork_url"], "/images/../secret")

    assert {:error, :invalid_case_cards} = ResponseMatrix.validate(traversal_artwork)

    thirteen_cards =
      Enum.map(0..12, fn index ->
        card
        |> Map.put("id", "card-#{index}")
        |> Map.delete("code")
      end)

    assert {:error, :too_many_case_cards} =
             ResponseMatrix.validate(%{definition | "case_cards" => thirteen_cards})
  end

  test "validates server-owned Search cards and their reveal instructions" do
    valid =
      valid_case()
      |> Map.put("case_cards", [
        %{
          "id" => "receipt",
          "code" => "A",
          "title" => "Receipt",
          "type" => "evidence",
          "takeable" => true,
          "initially_known" => false
        }
      ])
      |> Map.put("search_results", %{
        "locations" => %{
          "51" => search_result(["receipt"], ["receipt"])
        },
        "suspects" => %{
          "suspect" => search_result([], [])
        },
        "all_other_locations" => search_result([], [])
      })

    assert :ok = Validator.validate(valid)

    invalid_target =
      put_in(valid["search_results"]["locations"]["nowhere"], search_result([], []))

    assert {:error, :invalid_search_results} = Validator.validate(invalid_target)

    invalid_card =
      put_in(
        valid["search_results"]["locations"]["51"]["reveal_case_card_ids"],
        ["missing"]
      )

    assert {:error, :invalid_search_results} = Validator.validate(invalid_card)

    taken_without_reveal =
      put_in(valid["search_results"]["locations"]["51"]["reveal_case_card_ids"], [])

    assert {:error, :invalid_search_results} = Validator.validate(taken_without_reveal)

    missing_suspect_card =
      update_in(valid["search_results"]["suspects"], &Map.delete(&1, "suspect"))

    assert {:error, :invalid_search_results} = Validator.validate(missing_suspect_card)
  end

  test "validates finite accusation options and solution references" do
    valid =
      valid_case()
      |> Map.put("case_cards", [
        %{
          "id" => "letter-opener",
          "code" => "A",
          "title" => "Letter Opener",
          "type" => "evidence",
          "initially_known" => true
        }
      ])
      |> Map.put("accusation_options", %{
        "weapons" => [
          %{
            "id" => "letter-opener",
            "label" => "Letter Opener",
            "case_card_id" => "letter-opener"
          }
        ],
        "motives" => [%{"id" => "blackmail", "label" => "Stop the blackmail"}]
      })
      |> Map.put("solution", %{
        "suspect_id" => "suspect",
        "weapon_id" => "letter-opener",
        "motive_id" => "blackmail"
      })

    assert :ok = Validator.validate(valid)

    invalid_weapon = put_in(valid["solution"]["weapon_id"], "missing")
    assert {:error, :invalid_accusation_options} = Validator.validate(invalid_weapon)

    invalid_case_card =
      update_in(valid["accusation_options"]["weapons"], fn [weapon] ->
        [Map.put(weapon, "case_card_id", "missing")]
      end)

    assert {:error, :invalid_accusation_options} = Validator.validate(invalid_case_card)
  end

  test "validates allow-listed special rules and their server-owned references" do
    case_definition =
      valid_case()
      |> Map.put("case_cards", [
        %{
          "id" => "late-report",
          "code" => "A",
          "title" => "Late Report",
          "type" => "information",
          "initially_known" => false
        }
      ])
      |> Map.put("special_rules", [
        starting_days_rule(),
        %{
          "id" => "late-witness",
          "title" => "Late Witness",
          "text" => "At the start of Day 2, reveal the witness and report.",
          "visibility" => "chisel",
          "trigger" => "day_started",
          "effect" => %{
            "type" => "day_reveal",
            "day" => 2,
            "reveal_case_card_ids" => ["late-report"],
            "reveal_suspect_ids" => ["suspect"]
          }
        }
      ])

    assert :ok = Validator.validate(case_definition)
    assert SpecialRules.starting_days(case_definition, 3, 8) == 5
    assert Enum.map(SpecialRules.day_rules(case_definition, 2), & &1["id"]) == ["late-witness"]

    invalid_reference =
      put_in(
        case_definition,
        ["special_rules", Access.at(1), "effect", "reveal_case_card_ids"],
        ["missing"]
      )

    assert {:error, :invalid_special_rules} = Validator.validate(invalid_reference)

    unknown_effect =
      put_in(
        case_definition,
        ["special_rules", Access.at(1), "effect", "type"],
        "run_case_script"
      )

    assert {:error, :invalid_special_rules} = Validator.validate(unknown_effect)

    unreachable_day =
      put_in(
        case_definition,
        ["special_rules", Access.at(1), "effect", "day"],
        7
      )

    assert {:error, :invalid_special_rules} = Validator.validate(unreachable_day)

    duplicate_setup =
      Map.update!(case_definition, "special_rules", &[starting_days_rule() | &1])

    assert {:error, :invalid_special_rules} = Validator.validate(duplicate_setup)
  end

  test "validates finite special actors, blockers, and private interaction effects" do
    valid =
      valid_case()
      |> Map.put("case_cards", [
        %{
          "id" => "sealed-file",
          "code" => "A",
          "title" => "Sealed File",
          "type" => "information",
          "initially_known" => false
        }
      ])
      |> Map.put("special_actors", [special_actor()])

    assert :ok = Validator.validate(valid)

    invalid_location = put_in(valid, ["special_actors", Access.at(0), "location_id"], "404")
    assert {:error, :invalid_special_actors} = Validator.validate(invalid_location)

    invalid_card =
      put_in(
        valid,
        [
          "special_actors",
          Access.at(0),
          "options",
          Access.at(0),
          "effects",
          Access.at(1),
          "case_card_ids"
        ],
        ["missing"]
      )

    assert {:error, :invalid_special_actors} = Validator.validate(invalid_card)

    unknown_block =
      put_in(valid, ["special_actors", Access.at(0), "blocks"], ["steal_solution"])

    assert {:error, :invalid_special_actors} = Validator.validate(unknown_block)

    unknown_effect =
      put_in(
        valid,
        [
          "special_actors",
          Access.at(0),
          "options",
          Access.at(0),
          "effects",
          Access.at(0),
          "type"
        ],
        "run_case_script"
      )

    assert {:error, :invalid_special_actors} = Validator.validate(unknown_effect)

    hidden_but_active =
      put_in(valid, ["special_actors", Access.at(0), "initially_visible"], false)

    assert {:error, :invalid_special_actors} = Validator.validate(hidden_but_active)
  end

  test "validates mutually exclusive special actor branches and referenced effects" do
    first_option =
      special_actor()
      |> get_in(["options", Access.at(0)])
      |> Map.put("choice_group", "tail-approach")

    second_option = %{
      "id" => "shadow-tail",
      "label" => "Shadow the lookout",
      "action_cost" => 2,
      "scratch_cost" => 0,
      "once" => true,
      "choice_group" => "tail-approach",
      "effects" => [
        %{"type" => "move_actor", "location_id" => "96"},
        %{"type" => "public_case_cards", "case_card_ids" => ["sealed-file"]},
        %{"type" => "reveal_suspects", "suspect_ids" => ["suspect"]}
      ]
    }

    actor = put_in(special_actor(), ["options"], [first_option, second_option])

    valid =
      valid_case()
      |> Map.put("case_cards", [
        %{
          "id" => "sealed-file",
          "code" => "A",
          "title" => "Sealed File",
          "type" => "information",
          "initially_known" => false
        }
      ])
      |> Map.put("special_actors", [actor])

    assert :ok = Validator.validate(valid)

    single_branch =
      put_in(valid, ["special_actors", Access.at(0), "options"], [first_option])

    assert {:error, :invalid_special_actors} = Validator.validate(single_branch)

    invalid_destination =
      put_in(
        valid,
        [
          "special_actors",
          Access.at(0),
          "options",
          Access.at(1),
          "effects",
          Access.at(0),
          "location_id"
        ],
        "404"
      )

    assert {:error, :invalid_special_actors} = Validator.validate(invalid_destination)

    invalid_suspect =
      put_in(
        valid,
        [
          "special_actors",
          Access.at(0),
          "options",
          Access.at(1),
          "effects",
          Access.at(2),
          "suspect_ids"
        ],
        ["missing"]
      )

    assert {:error, :invalid_special_actors} = Validator.validate(invalid_suspect)
  end

  test "validates day-driven special actor reveal, activation, and movement" do
    hidden_actor =
      special_actor()
      |> Map.put("initially_visible", false)
      |> Map.put("initially_active", false)

    valid =
      valid_case()
      |> Map.put("case_cards", [
        %{
          "id" => "sealed-file",
          "code" => "A",
          "title" => "Sealed File",
          "type" => "information",
          "initially_known" => false
        }
      ])
      |> Map.put("special_actors", [hidden_actor])
      |> Map.put("special_rules", [
        %{
          "id" => "tail-arrives",
          "title" => "A Tail Appears",
          "text" => "At the start of Day 2, place the tail at the pier.",
          "visibility" => "chisel",
          "trigger" => "day_started",
          "effect" => %{
            "type" => "day_reveal",
            "day" => 2,
            "special_actor_updates" => [
              %{
                "actor_id" => "station-tail",
                "visible" => true,
                "active" => true,
                "location_id" => "96"
              }
            ]
          }
        }
      ])

    assert :ok = Validator.validate(valid)
    assert Enum.map(SpecialRules.day_rules(valid, 2), & &1["id"]) == ["tail-arrives"]

    invalid_actor =
      put_in(
        valid,
        [
          "special_rules",
          Access.at(0),
          "effect",
          "special_actor_updates",
          Access.at(0),
          "actor_id"
        ],
        "missing"
      )

    assert {:error, :invalid_special_rules} = Validator.validate(invalid_actor)

    invalid_location =
      put_in(
        valid,
        [
          "special_rules",
          Access.at(0),
          "effect",
          "special_actor_updates",
          Access.at(0),
          "location_id"
        ],
        "404"
      )

    assert {:error, :invalid_special_rules} = Validator.validate(invalid_location)

    hidden_update =
      put_in(
        valid,
        [
          "special_rules",
          Access.at(0),
          "effect",
          "special_actor_updates",
          Access.at(0),
          "visible"
        ],
        false
      )

    assert {:error, :invalid_special_rules} = Validator.validate(hidden_update)

    malformed_update =
      put_in(
        valid,
        ["special_rules", Access.at(0), "effect", "special_actor_updates"],
        [nil]
      )

    assert {:error, :invalid_special_rules} = Validator.validate(malformed_update)
  end

  defp valid_case do
    %{
      "board_id" => "dcoa_classic",
      "suspects" => [%{"id" => "suspect", "location_id" => "96"}]
    }
  end

  defp search_result(reveal_ids, take_ids) do
    %{
      "text" => "A case-owned Search card.",
      "archive" => true,
      "reveal_case_card_ids" => reveal_ids,
      "take_case_card_ids" => take_ids,
      "reveal_suspect_ids" => []
    }
  end

  defp starting_days_rule do
    %{
      "id" => "short-clock",
      "title" => "Short Clock",
      "text" => "Use the shortened Day track for this case.",
      "visibility" => "public",
      "trigger" => "setup",
      "effect" => %{
        "type" => "starting_days",
        "days_by_detective_count" => %{"2" => 6, "3" => 5, "4" => 4}
      }
    }
  end

  defp special_actor do
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
          "effects" => [
            %{"type" => "disable_actor"},
            %{"type" => "private_case_cards", "case_card_ids" => ["sealed-file"]}
          ]
        }
      ]
    }
  end

  defp legacy_fixture_locations do
    [
      location("central-precinct", "Central Precinct", "police_station", ["central"], 0.25, 0.35),
      location("canal-gate", "Canal Gate", "standard", ["central", "harbor"], 0.5, 0.5),
      location("pier-club", "Pier Club", "mob_joint", ["harbor"], 0.75, 0.7)
    ]
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
