defmodule Detective.Cases.BoardCatalog do
  @moduledoc "Loads immutable server-owned board topology."

  @catalog_path :detective
                |> :code.priv_dir()
                |> List.to_string()
                |> Path.join("board/dcoa_classic.json")
  @external_resource @catalog_path
  @catalog @catalog_path |> File.read!() |> Jason.decode!()
  @catalog_id @catalog["id"]

  def fetch(@catalog_id), do: {:ok, @catalog}
  def fetch(_board_id), do: {:error, :unknown_board}

  def locations(board_id) do
    with {:ok, board} <- fetch(board_id), do: {:ok, board["locations"]}
  end

  def location(board_id, location_id) when is_binary(location_id) do
    with {:ok, locations} <- locations(board_id),
         %{} = location <- Enum.find(locations, &(&1["id"] == location_id)) do
      {:ok, location}
    else
      nil -> {:error, :unknown_location}
      {:error, reason} -> {:error, reason}
    end
  end

  def location(_board_id, _location_id), do: {:error, :unknown_location}
end
