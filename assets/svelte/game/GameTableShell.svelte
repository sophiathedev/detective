<script>
  import { onMount } from "svelte"

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
  let fullscreenActive = $state(false)
  let fullscreenSupported = $state(false)
  let fullscreenError = $state(false)

  function fullscreenElement() {
    return document.fullscreenElement ?? document.webkitFullscreenElement ?? null
  }

  function updateFullscreenState() {
    fullscreenActive = fullscreenElement()?.id === "game-table-shell"
    fullscreenError = false
  }

  async function toggleFullscreen() {
    const table = document.getElementById("game-table-shell")
    if (!table || !fullscreenSupported) return

    try {
      if (fullscreenActive) {
        const exit = document.exitFullscreen ?? document.webkitExitFullscreen
        await exit.call(document)
      } else {
        const request = table.requestFullscreen ?? table.webkitRequestFullscreen
        await request.call(table)
      }

      updateFullscreenState()
      document.getElementById("game-table-menu")?.removeAttribute("open")
    } catch (_error) {
      fullscreenError = true
    }
  }

  onMount(() => {
    const table = document.getElementById("game-table-shell")
    const request = table?.requestFullscreen ?? table?.webkitRequestFullscreen
    const exit = document.exitFullscreen ?? document.webkitExitFullscreen

    fullscreenSupported = Boolean(request && exit)
    updateFullscreenState()

    document.addEventListener("fullscreenchange", updateFullscreenState)
    document.addEventListener("webkitfullscreenchange", updateFullscreenState)

    return () => {
      document.removeEventListener("fullscreenchange", updateFullscreenState)
      document.removeEventListener("webkitfullscreenchange", updateFullscreenState)
    }
  })
</script>

<main id="game-table-shell" class="noir-game-table">
  <section id="game-map-region" class="noir-game-map-region" aria-label="Investigation map">
    {@render mapStage?.()}
  </section>

  <header id="game-phase-plaque" class="noir-game-phase" aria-live="polite">
    <details id="game-table-menu" class="noir-game-table-menu" aria-live="off">
      <summary id="game-table-menu-toggle" aria-label="Open case menu">
        <span class="noir-game-table-menu-sigil" aria-hidden="true">
          <i></i>
          <i></i>
          <i></i>
        </span>
      </summary>

      <div class="noir-game-table-menu-panel">
        <div class="noir-game-table-menu-heading">
          <span>Table controls</span>
          <strong>Case navigation</strong>
        </div>

        <button
          id="game-toggle-fullscreen"
          type="button"
          aria-pressed={fullscreenActive}
          disabled={!fullscreenSupported}
          onclick={toggleFullscreen}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
            <path d="M9 4H4v5M15 4h5v5M9 20H4v-5M15 20h5v-5" />
          </svg>
          <span>
            <strong>{fullscreenActive ? "Exit fullscreen" : "Fill the screen"}</strong>
            <small>{fullscreenSupported ? "Esc returns to the desk" : "Unavailable in this browser"}</small>
          </span>
        </button>

        {#if fullscreenError}
          <p id="game-fullscreen-error" role="status">
            Fullscreen could not start. Browser controls remain available.
          </p>
        {/if}

        <nav aria-label="Case navigation">
          <a id="game-return-dashboard" href="/dashboard">Dashboard</a>
          <a id="game-account-settings" href="/users/settings">Settings</a>
          <a
            id="game-account-log-out"
            href="/users/log-out"
            data-method="delete"
            data-to="/users/log-out"
          >Log out</a>
        </nav>
      </div>
    </details>

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
