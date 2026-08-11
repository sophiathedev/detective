defmodule Detective.Repo.Migrations.AddGameResultMetadata do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :winner_role, :string
      add :winner_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :finish_reason, :string
    end

    execute(
      """
      UPDATE games AS game
      SET winner_role = snapshot.state_json->'winner'->>'role',
          winner_user_id = player.user_id,
          finish_reason = snapshot.state_json->'winner'->>'reason',
          finished_at = COALESCE(game.finished_at, snapshot.inserted_at)
      FROM (
        SELECT DISTINCT ON (game_id) game_id, state_json, inserted_at
        FROM game_snapshots
        ORDER BY game_id, version DESC
      ) AS snapshot
      LEFT JOIN game_players AS player
        ON player.id::text = snapshot.state_json->'winner'->>'player_id'
      WHERE game.id = snapshot.game_id
        AND game.status = 'finished'
        AND snapshot.state_json->'winner' IS NOT NULL
      """,
      "SELECT 1"
    )

    create index(:games, [:winner_user_id])

    create constraint(:games, :games_winner_role_check,
             check: "winner_role IS NULL OR winner_role IN ('detective', 'chisel')"
           )
  end
end
