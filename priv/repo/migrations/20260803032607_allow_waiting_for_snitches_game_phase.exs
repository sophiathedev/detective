defmodule Detective.Repo.Migrations.AllowWaitingForSnitchesGamePhase do
  use Ecto.Migration

  def up do
    drop constraint(:games, :games_phase_check)

    create constraint(:games, :games_phase_check,
             check:
               "phase IN ('lobby', 'briefing', 'detective_turn', 'waiting_for_chisel', 'waiting_for_snitches', 'waiting_for_detective_decision', 'resolving_challenge', 'accusation', 'paused', 'finished')"
           )
  end

  def down do
    drop constraint(:games, :games_phase_check)

    create constraint(:games, :games_phase_check,
             check:
               "phase IN ('lobby', 'briefing', 'detective_turn', 'waiting_for_chisel', 'waiting_for_detective_decision', 'resolving_challenge', 'accusation', 'paused', 'finished')"
           )
  end
end
