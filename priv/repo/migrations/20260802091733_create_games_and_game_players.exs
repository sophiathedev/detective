defmodule Detective.Repo.Migrations.CreateGamesAndGamePlayers do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :room_code, :string, null: false
      add :host_user_id, references(:users, type: :binary_id), null: false
      add :case_version_id, references(:case_versions, type: :binary_id), null: false
      add :status, :string, null: false, default: "waiting"
      add :phase, :string, null: false, default: "lobby"
      add :max_detectives, :integer, null: false
      add :current_version, :integer, null: false, default: 0
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:games, [:room_code])
    create index(:games, [:host_user_id])
    create index(:games, [:case_version_id])

    create constraint(:games, :games_status_check,
             check: "status IN ('waiting', 'active', 'finished', 'cancelled')"
           )

    create constraint(:games, :games_phase_check,
             check:
               "phase IN ('lobby', 'briefing', 'detective_turn', 'waiting_for_chisel', 'waiting_for_detective_decision', 'resolving_challenge', 'accusation', 'paused', 'finished')"
           )

    create constraint(:games, :games_max_detectives_check,
             check: "max_detectives BETWEEN 1 AND 4"
           )

    create constraint(:games, :games_current_version_check, check: "current_version >= 0")

    create table(:game_players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id), null: false
      add :role, :string, null: false
      add :seat, :integer
      add :ready, :boolean, null: false, default: false
      add :status, :string, null: false, default: "active"
      add :joined_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_players, [:game_id, :user_id])

    create unique_index(:game_players, [:game_id],
             where: "role = 'chisel'",
             name: :one_chisel_per_game
           )

    create unique_index(:game_players, [:game_id, :seat],
             where: "seat IS NOT NULL AND status = 'active'",
             name: :unique_active_seat_per_game
           )

    create index(:game_players, [:user_id, :status])

    create constraint(:game_players, :game_players_role_check,
             check: "role IN ('chisel', 'detective')"
           )

    create constraint(:game_players, :game_players_status_check,
             check: "status IN ('active', 'left', 'removed')"
           )

    create constraint(:game_players, :game_players_seat_check, check: "seat IS NULL OR seat > 0")
  end
end
