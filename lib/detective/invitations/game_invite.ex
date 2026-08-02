defmodule Detective.Invitations.GameInvite do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Accounts.User
  alias Detective.Games.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_invites" do
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :max_uses, :integer
    field :use_count, :integer, default: 0

    belongs_to :game, Game
    belongs_to :created_by_user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [])
    |> validate_required([
      :game_id,
      :created_by_user_id,
      :token_hash,
      :expires_at,
      :max_uses,
      :use_count
    ])
    |> validate_number(:max_uses, greater_than: 0)
    |> validate_number(:use_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:game_id)
    |> foreign_key_constraint(:created_by_user_id)
    |> unique_constraint(:token_hash)
  end
end
