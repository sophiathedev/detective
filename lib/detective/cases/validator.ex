defmodule Detective.Cases.Validator do
  @moduledoc """
  Validates the structural rules required by the authoritative engine.
  """

  alias Detective.Cases.{
    AccusationSheet,
    BoardCatalog,
    BoardTopology,
    LegacyBoardAdapter,
    ResponseMatrix,
    SearchDeck,
    SpecialRules
  }

  def validate(case_definition) when is_map(case_definition) do
    with {:ok, case_definition} <- LegacyBoardAdapter.adapt(case_definition),
         {:ok, locations} <- BoardCatalog.locations(case_definition["board_id"]),
         :ok <- BoardTopology.validate(locations),
         :ok <- validate_suspect_locations(case_definition["suspects"], locations),
         :ok <- ResponseMatrix.validate(case_definition),
         :ok <- SearchDeck.validate(case_definition, locations),
         :ok <- SpecialRules.validate(case_definition),
         :ok <- AccusationSheet.validate(case_definition) do
      :ok
    end
  end

  def validate(_case_definition), do: {:error, :invalid_case_definition}

  defp validate_suspect_locations(nil, _locations), do: :ok

  defp validate_suspect_locations(suspects, locations) when is_list(suspects) do
    location_ids = locations |> Enum.map(& &1["id"]) |> MapSet.new()

    if Enum.all?(suspects, fn suspect ->
         is_map(suspect) and is_binary(suspect["id"]) and
           MapSet.member?(location_ids, suspect["location_id"])
       end) do
      :ok
    else
      {:error, :invalid_suspect_location}
    end
  end

  defp validate_suspect_locations(_suspects, _locations),
    do: {:error, :invalid_suspects}
end
