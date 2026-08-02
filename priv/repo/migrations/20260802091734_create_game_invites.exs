defmodule Detective.Repo.Migrations.CreateGameInvites do
  use Ecto.Migration

  def change do
    create table(:game_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id), null: false
      add :created_by_user_id, references(:users, type: :binary_id), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :max_uses, :integer, null: false
      add :use_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_invites, [:token_hash])
    create index(:game_invites, [:game_id])

    create constraint(:game_invites, :game_invites_max_uses_check, check: "max_uses > 0")

    create constraint(:game_invites, :game_invites_use_count_check,
             check: "use_count >= 0 AND use_count <= max_uses"
           )
  end
end
