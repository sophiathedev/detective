defmodule Detective.Repo.Migrations.CreatePlayerNotes do
  use Ecto.Migration

  def change do
    create table(:player_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :content, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:player_notes, [:game_id, :user_id])
  end
end
