defmodule Detective.Cases.SearchDeckTest do
  use ExUnit.Case, async: true

  alias Detective.Cases.{BoardCatalog, SearchDeck}

  test "standalone validation rejects binary suspects without raising" do
    result =
      validation_result(fn ->
        valid_case() |> Map.put("suspects", "suspect") |> SearchDeck.validate()
      end)

    assert result == {:error, :invalid_search_results}
  end

  test "standalone validation rejects map case cards without raising" do
    result =
      validation_result(fn ->
        valid_case() |> Map.put("case_cards", %{"id" => "card"}) |> SearchDeck.validate()
      end)

    assert result == {:error, :invalid_search_results}
  end

  test "standalone validation rejects malformed entries without raising" do
    assert {:error, :invalid_search_results} =
             valid_case() |> Map.put("suspects", [nil]) |> SearchDeck.validate()

    assert {:error, :invalid_search_results} =
             valid_case() |> Map.put("case_cards", [nil]) |> SearchDeck.validate()
  end

  test "reused validation rejects malformed resolved locations without raising" do
    assert {:error, :invalid_search_results} = SearchDeck.validate(valid_case(), [nil])

    assert {:error, :invalid_search_results} =
             SearchDeck.validate(valid_case(), [%{"id" => nil}])

    assert {:error, :invalid_search_results} = SearchDeck.validate(valid_case(), "locations")
  end

  test "reused validation rejects malformed case collections without raising" do
    result =
      validation_result(fn ->
        SearchDeck.validate(Map.put(valid_case(), "suspects", "suspect"), board_locations())
      end)

    assert result == {:error, :invalid_search_results}
  end

  test "standalone validation preserves the unknown-board domain error" do
    assert {:error, :unknown_board} =
             valid_case() |> Map.put("board_id", "missing") |> SearchDeck.validate()
  end

  test "legacy validation rejects raw canonical Search location keys through both entry points" do
    Enum.each(["51", 51], fn invalid_location_id ->
      legacy = legacy_case(%{invalid_location_id => search_result()})

      assert {:error, :invalid_search_results} = SearchDeck.validate(legacy)
      assert {:error, :invalid_search_results} = SearchDeck.validate(legacy, board_locations())
    end)
  end

  test "legacy validation rejects mixed old and canonical Search keys through both entry points" do
    legacy =
      legacy_case(%{
        "central-precinct" => search_result(),
        "51" => search_result()
      })

    assert {:error, :invalid_search_results} = SearchDeck.validate(legacy)
    assert {:error, :invalid_search_results} = SearchDeck.validate(legacy, board_locations())
  end

  defp valid_case do
    %{
      "board_id" => "dcoa_classic",
      "suspects" => [%{"id" => "suspect"}],
      "case_cards" => [%{"id" => "card"}],
      "search_results" => %{
        "locations" => %{"51" => search_result()},
        "suspects" => %{"suspect" => search_result()},
        "all_other_locations" => search_result()
      }
    }
  end

  defp board_locations do
    assert {:ok, locations} = BoardCatalog.locations("dcoa_classic")
    locations
  end

  defp legacy_case(search_locations) do
    %{
      "locations" => legacy_fixture_locations(),
      "suspects" => [%{"id" => "suspect", "location_id" => "central-precinct"}],
      "case_cards" => [%{"id" => "card"}],
      "search_results" => %{
        "locations" => search_locations,
        "suspects" => %{"suspect" => search_result()},
        "all_other_locations" => search_result()
      }
    }
  end

  defp legacy_fixture_locations do
    [
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
    ]
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

  defp search_result do
    %{
      "text" => "A result.",
      "archive" => false,
      "reveal_case_card_ids" => [],
      "take_case_card_ids" => [],
      "reveal_suspect_ids" => []
    }
  end

  defp validation_result(fun) do
    fun.()
  rescue
    error -> {:raised, error.__struct__}
  end
end
