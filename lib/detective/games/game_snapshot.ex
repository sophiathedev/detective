defmodule Detective.Games.GameSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Games.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_snapshots" do
    field :version, :integer
    field :schema_version, :integer
    field :state_json, :map, redact: true

    belongs_to :game, Game

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def insert_changeset(snapshot) do
    snapshot
    |> change()
    |> validate_required([:game_id, :version, :schema_version, :state_json])
    |> validate_number(:version, greater_than_or_equal_to: 0)
    |> validate_number(:schema_version, greater_than: 0)
    |> unique_constraint([:game_id, :version])
  end
end
