<script>
  let {
    phase,
    day,
    daysRemaining,
    activeDetectiveName,
    connectionState,
    version,
    detectiveRail,
    chiselConsole,
    mapStage,
    contextStack,
    actionRail,
    overlay,
  } = $props()

  let phaseLabel = $derived(String(phase ?? "waiting").replaceAll("_", " "))
</script>

<main id="game-table-shell" class="noir-game-table">
  <section id="game-map-region" class="noir-game-map-region" aria-label="Investigation map">
    {@render mapStage?.()}
  </section>

  <header id="game-phase-plaque" class="noir-game-phase" aria-live="polite">
    <span>Day {day} · {daysRemaining} remaining</span>
    <strong>{phaseLabel} · {activeDetectiveName ?? "No active Detective"}</strong>
    <span>{connectionState} · v{version}</span>
  </header>

  <aside id="game-detective-rail-region" class="noir-game-detective-rail" aria-label="Detectives">
    {@render detectiveRail?.()}
  </aside>

  <aside id="game-chisel-region" class="noir-game-chisel" aria-label="Chisel">
    {@render chiselConsole?.()}
  </aside>

  <aside id="game-context-region" class="noir-game-context" aria-label="Current context">
    {@render contextStack?.()}
  </aside>

  <nav id="game-action-region" class="noir-game-actions" aria-label="Game actions">
    {@render actionRail?.()}
  </nav>

  <aside class="noir-map-rotate-notice" aria-live="polite">
    Rotate to landscape to interact with the map. Casebook and game status remain available.
  </aside>

  <div id="game-overlay-region">
    {@render overlay?.()}
  </div>
</main>
