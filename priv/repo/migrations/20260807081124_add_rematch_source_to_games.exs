defmodule Detective.Repo.Migrations.AddRematchSourceToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :rematch_of_game_id,
          references(:games, type: :binary_id, on_delete: :nilify_all)
    end

    create unique_index(:games, [:rematch_of_game_id], where: "rematch_of_game_id IS NOT NULL")
  end
end
