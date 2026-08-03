defmodule Detective.Cases.ValidatorTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.Validator

  test "accepts border locations that keep every location within three Move actions" do
    assert :ok = Validator.validate(valid_case())
  end

  test "rejects disconnected locations and missing Police Stations" do
    disconnected =
      update_in(valid_case()["locations"], fn locations ->
        [location("remote", "Remote", "standard", ["hills"]) | locations]
      end)

    assert {:error, :location_beyond_three_moves} = Validator.validate(disconnected)

    without_station =
      update_in(valid_case()["locations"], fn locations ->
        Enum.map(locations, &Map.put(&1, "type", "standard"))
      end)

    assert {:error, :police_station_required} = Validator.validate(without_station)
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
          "precinct" => search_result(["receipt"], ["receipt"])
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
        valid["search_results"]["locations"]["precinct"]["reveal_case_card_ids"],
        ["missing"]
      )

    assert {:error, :invalid_search_results} = Validator.validate(invalid_card)

    taken_without_reveal =
      put_in(valid["search_results"]["locations"]["precinct"]["reveal_case_card_ids"], [])

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
      "locations" => [
        location("precinct", "Precinct", "police_station", ["central"]),
        location("border", "Border", "standard", ["central", "harbor"]),
        location("pier", "Pier", "mob_joint", ["harbor"])
      ],
      "suspects" => [%{"id" => "suspect", "location_id" => "pier"}]
    }
  end

  defp location(id, name, type, districts) do
    %{
      "id" => id,
      "name" => name,
      "type" => type,
      "district_ids" => districts,
      "x" => 0.5,
      "y" => 0.5
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
end
