defmodule Detective.Repo.Migrations.CreateGameRuntimeTables do
  use Ecto.Migration

  def change do
    create table(:game_commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :command_id, :uuid, null: false
      add :actor_id, references(:users, type: :binary_id), null: false
      add :command_type, :string, null: false
      add :payload_digest, :binary, null: false
      add :expected_version, :integer, null: false
      add :accepted_version, :integer, null: false
      add :reply_json, :map, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:game_commands, [:game_id, :command_id])
    create index(:game_commands, [:game_id, :accepted_version])

    create constraint(:game_commands, :game_commands_version_check,
             check: "expected_version >= 0 AND accepted_version = expected_version + 1"
           )

    create table(:game_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :command_id, :uuid, null: false
      add :sequence, :integer, null: false
      add :event_type, :string, null: false
      add :public_payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:game_events, [:game_id, :sequence])
    create index(:game_events, [:game_id, :command_id])

    create constraint(:game_events, :game_events_sequence_check, check: "sequence > 0")

    create table(:game_private_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false

      add :game_event_id,
          references(:game_events, type: :binary_id, on_delete: :delete_all),
          null: false

      add :recipient_user_id, references(:users, type: :binary_id), null: false
      add :payload, :map, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:game_private_events, [:game_id, :recipient_user_id])
    create unique_index(:game_private_events, [:game_event_id, :recipient_user_id])

    create table(:game_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :schema_version, :integer, null: false
      add :state_json, :map, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:game_snapshots, [:game_id, :version])

    create constraint(:game_snapshots, :game_snapshots_version_check,
             check: "version >= 0 AND schema_version > 0"
           )
  end
end
