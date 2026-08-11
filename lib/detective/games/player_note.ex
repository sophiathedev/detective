defmodule Detective.Games.PlayerNote do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Accounts.User
  alias Detective.Games.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "player_notes" do
    field :content, :string

    belongs_to :game, Game
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:content])
    |> validate_required([:game_id, :user_id, :content])
    |> validate_length(:content, max: 5_000)
    |> foreign_key_constraint(:game_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:game_id, :user_id])
  end
end
