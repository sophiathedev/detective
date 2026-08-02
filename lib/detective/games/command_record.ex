defmodule Detective.Games.CommandRecord do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Accounts.User
  alias Detective.Games.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_commands" do
    field :command_id, Ecto.UUID
    field :command_type, :string
    field :payload_digest, :binary, redact: true
    field :expected_version, :integer
    field :accepted_version, :integer
    field :reply_json, :map

    belongs_to :game, Game
    belongs_to :actor, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def insert_changeset(record) do
    record
    |> change()
    |> validate_required([
      :game_id,
      :command_id,
      :actor_id,
      :command_type,
      :payload_digest,
      :expected_version,
      :accepted_version,
      :reply_json
    ])
    |> unique_constraint([:game_id, :command_id])
  end
end
