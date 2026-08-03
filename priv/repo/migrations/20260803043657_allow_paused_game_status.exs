defmodule Detective.Repo.Migrations.AllowPausedGameStatus do
  use Ecto.Migration

  def up do
    drop constraint(:games, :games_status_check)

    create constraint(:games, :games_status_check,
             check: "status IN ('waiting', 'active', 'paused', 'finished', 'cancelled')"
           )
  end

  def down do
    drop constraint(:games, :games_status_check)

    create constraint(:games, :games_status_check,
             check: "status IN ('waiting', 'active', 'finished', 'cancelled')"
           )
  end
end
