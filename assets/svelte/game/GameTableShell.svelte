<script>
  import { onMount } from "svelte"
  import { useI18n } from "../i18n"

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
    returnPath = "/dashboard",
    csrfToken = "",
  } = $props()
  const { locale, t } = useI18n()

  let phaseLabel = $derived.by(() => {
    const phaseKey = String(phase ?? "waiting")
    const translated = t(phaseKey)
    return translated === phaseKey ? phaseKey.replaceAll("_", " ") : translated
  })
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

  function localePath(nextLocale) {
    return `/locale/${nextLocale}?return_to=${encodeURIComponent(returnPath)}`
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
  <section id="game-map-region" class="noir-game-map-region" aria-label={t("Investigation map")}>
    {@render mapStage?.()}
  </section>

  <header id="game-phase-plaque" class="noir-game-phase" aria-live="polite">
    <details id="game-table-menu" class="noir-game-table-menu" aria-live="off">
      <summary id="game-table-menu-toggle" aria-label={t("Open case menu")}>
        <span class="noir-game-table-menu-sigil" aria-hidden="true">
          <i></i>
          <i></i>
          <i></i>
        </span>
      </summary>

      <div class="noir-game-table-menu-panel">
        <div class="noir-game-table-menu-heading">
          <span>{t("Table controls")}</span>
          <strong>{t("Case navigation")}</strong>
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
            <strong>{fullscreenActive ? t("Exit fullscreen") : t("Fill the screen")}</strong>
            <small>{fullscreenSupported ? t("Esc returns to the desk") : t("Unavailable in this browser")}</small>
          </span>
        </button>

        {#if fullscreenError}
          <p id="game-fullscreen-error" role="status">
            {t("Fullscreen could not start. Browser controls remain available.")}
          </p>
        {/if}

        <nav aria-label={t("Case navigation")}>
          <a id="game-return-dashboard" href="/dashboard">{t("Dashboard")}</a>
          <a id="game-account-settings" href="/users/settings">{t("Settings")}</a>
          <a
            id="game-account-log-out"
            href="/users/log-out"
            data-method="delete"
            data-csrf={csrfToken}
            data-to="/users/log-out"
          >{t("Log out")}</a>
        </nav>

        <div class="noir-game-table-locale" role="group" aria-label={t("Language")}>
          <a
            id="game-locale-en"
            href={localePath("en")}
            data-method="post"
            data-csrf={csrfToken}
            data-to={localePath("en")}
            aria-current={locale === "en" ? "true" : undefined}
          >EN</a>
          <a
            id="game-locale-vi"
            href={localePath("vi")}
            data-method="post"
            data-csrf={csrfToken}
            data-to={localePath("vi")}
            aria-current={locale === "vi" ? "true" : undefined}
          >VI</a>
        </div>
      </div>
    </details>

    <span>{t("Day {day} · {remaining} remaining", { day, remaining: daysRemaining })}</span>
    <strong>{t("{phase} · {detective}", { phase: phaseLabel, detective: activeDetectiveName ?? t("No active Detective") })}</strong>
    <span>{t("{connection} · v{version}", { connection: t(connectionState), version })}</span>
  </header>

  <aside id="game-detective-rail-region" class="noir-game-detective-rail" aria-label={t("Detectives")}>
    {@render detectiveRail?.()}
  </aside>

  <aside id="game-chisel-region" class="noir-game-chisel" aria-label={t("Chisel")}>
    {@render chiselConsole?.()}
  </aside>

  <aside id="game-context-region" class="noir-game-context" aria-label={t("Current context")}>
    {@render contextStack?.()}
  </aside>

  <nav id="game-action-region" class="noir-game-actions" aria-label={t("Game actions")}>
    {@render actionRail?.()}
  </nav>

  <aside class="noir-map-rotate-notice" aria-live="polite">
    {t("Rotate to landscape to interact with the map. Casebook and game status remain available.")}
  </aside>

  <div id="game-overlay-region">
    {@render overlay?.()}
  </div>
</main>
