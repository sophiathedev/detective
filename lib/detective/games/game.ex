defmodule Detective.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  alias Detective.Accounts.User
  alias Detective.Cases.CaseVersion
  alias Detective.Games.GamePlayer
  alias Detective.Invitations.GameInvite

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "games" do
    field :title, :string
    field :room_code, :string
    field :status, :string, default: "waiting"
    field :phase, :string, default: "lobby"
    field :max_detectives, :integer
    field :current_version, :integer, default: 0
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    belongs_to :host_user, User
    belongs_to :case_version, CaseVersion
    has_many :players, GamePlayer
    has_many :invites, GameInvite

    timestamps(type: :utc_datetime)
  end

  def create_changeset(game, attrs) do
    game
    |> cast(attrs, [:title, :case_version_id, :max_detectives])
    |> update_change(:room_code, &String.upcase/1)
    |> validate_required([
      :title,
      :room_code,
      :host_user_id,
      :case_version_id,
      :max_detectives,
      :status,
      :phase
    ])
    |> validate_length(:title, min: 3, max: 80)
    |> validate_format(:room_code, ~r/^[A-Z2-9]{6}$/)
    |> validate_inclusion(:status, ~w(waiting active paused finished cancelled))
    |> validate_inclusion(:phase, ~w(lobby))
    |> validate_number(:max_detectives, greater_than_or_equal_to: 1, less_than_or_equal_to: 4)
    |> validate_number(:current_version, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:host_user_id)
    |> foreign_key_constraint(:case_version_id)
    |> unique_constraint(:room_code)
  end

  def transition_changeset(game, attrs) do
    game
    |> change(attrs)
    |> validate_inclusion(:status, ~w(waiting active paused finished cancelled))
    |> validate_inclusion(
      :phase,
      ~w(lobby briefing detective_turn waiting_for_chisel waiting_for_snitches waiting_for_detective_decision resolving_challenge accusation paused finished)
    )
    |> validate_number(:current_version, greater_than_or_equal_to: 0)
  end
end
