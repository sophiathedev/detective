defmodule Detective.Games.GamePrivateEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Accounts.User
  alias Detective.Games.{Game, GameEvent}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_private_events" do
    field :payload, :map, redact: true

    belongs_to :game, Game
    belongs_to :game_event, GameEvent
    belongs_to :recipient_user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def insert_changeset(event) do
    event
    |> change()
    |> validate_required([:game_id, :game_event_id, :recipient_user_id, :payload])
    |> unique_constraint([:game_event_id, :recipient_user_id])
  end
end
