defmodule Detective.Games.GamePlayer do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Accounts.User
  alias Detective.Games.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_players" do
    field :role, :string
    field :seat, :integer
    field :ready, :boolean, default: false
    field :status, :string, default: "active"
    field :joined_at, :utc_datetime

    belongs_to :game, Game
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [])
    |> validate_required([:game_id, :user_id, :role, :ready, :status, :joined_at])
    |> validate_inclusion(:role, ~w(chisel detective))
    |> validate_inclusion(:status, ~w(active left removed))
    |> validate_number(:seat, greater_than: 0)
    |> foreign_key_constraint(:game_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:game_id, :user_id])
    |> unique_constraint(:game_id, name: :one_chisel_per_game)
    |> unique_constraint([:game_id, :seat], name: :unique_active_seat_per_game)
  end
end
