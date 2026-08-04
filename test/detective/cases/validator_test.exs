defmodule Detective.Cases.ValidatorTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.Validator

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
        }
      ])
      |> Map.put("response_matrix", %{
        "suspect" => %{
          "victim" => %{
            "most_useful" => "A useful answer.",
            "misdirections" => ["A false trail."]
          }
        }
      })

    assert :ok = Validator.validate(case_definition)

    invalid_reference = put_in(case_definition["response_matrix"]["unknown"], %{})
    assert {:error, :invalid_response_reference} = Validator.validate(invalid_reference)

    without_truth =
      put_in(
        case_definition["response_matrix"]["suspect"]["victim"]["most_useful"],
        ""
      )

    assert {:error, :invalid_response_matrix} = Validator.validate(without_truth)
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
