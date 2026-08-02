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
end
