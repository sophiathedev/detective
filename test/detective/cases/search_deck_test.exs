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
