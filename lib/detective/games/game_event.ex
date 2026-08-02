defmodule Detective.Games.GameEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Games.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_events" do
    field :command_id, Ecto.UUID
    field :sequence, :integer
    field :event_type, :string
    field :public_payload, :map

    belongs_to :game, Game

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def insert_changeset(event) do
    event
    |> change()
    |> validate_required([
      :game_id,
      :command_id,
      :sequence,
      :event_type,
      :public_payload
    ])
    |> validate_number(:sequence, greater_than: 0)
    |> unique_constraint([:game_id, :sequence])
  end
end
