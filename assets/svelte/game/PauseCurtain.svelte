<script>
  import { onDestroy } from "svelte"
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let {
    active = false,
    reason = null,
    offlinePlayers = [],
    canResume = false,
    commandPending = false,
    commandError = null,
    onResume = () => {},
  } = $props()

  let pauseDocument = $state(null)
  let returnFocus = null
  let wasActive = false

  function restoreFocus() {
    if (typeof window === "undefined") return

    const focusTarget = returnFocus
    returnFocus = null
    window.requestAnimationFrame(() => {
      if (focusTarget?.isConnected && typeof focusTarget.focus === "function") {
        focusTarget.focus({ preventScroll: true })
      }
    })
  }

  function keepFocusInside(event) {
    if (!active || event.key !== "Tab" || !pauseDocument) return

    const controls = [...pauseDocument.querySelectorAll("button:not(:disabled), [tabindex='0']")]
    if (controls.length === 0) {
      event.preventDefault()
      pauseDocument.focus({ preventScroll: true })
      return
    }

    const first = controls[0]
    const last = controls[controls.length - 1]
    const focusOutside = !pauseDocument.contains(document.activeElement)

    if (focusOutside || (!event.shiftKey && document.activeElement === last)) {
      event.preventDefault()
      first.focus({ preventScroll: true })
    } else if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus({ preventScroll: true })
    }
  }

  function pauseDescription(pauseReason, absentPlayers) {
    if (pauseReason === "player_disconnected") {
      if (absentPlayers.length === 0) {
        return t("Everyone is back at the table. The Chisel may reopen the case.")
      }

      const names = absentPlayers.map((player) => player.display_name).join(", ")
      return t("{names} left the table. The case stays sealed until they return.", { names })
    }

    if (typeof pauseReason === "string" && !pauseReason.includes("_")) return pauseReason

    return t("Play is paused while the table reconnects.")
  }

  $effect(() => {
    if (active && !wasActive && typeof document !== "undefined") {
      returnFocus = document.activeElement
      window.requestAnimationFrame(() => pauseDocument?.focus({ preventScroll: true }))
    } else if (!active && wasActive) {
      restoreFocus()
    }

    wasActive = active
  })

  onDestroy(() => {
    if (active) restoreFocus()
  })
</script>

<svelte:window onkeydown={keepFocusInside} />

{#if active}
  <div
    id="game-pause-curtain"
    class="game-pause-seal noir-pause-curtain"
    role="dialog"
    aria-modal="true"
    aria-labelledby="game-pause-heading"
    aria-describedby="game-pause-description"
  >
    <div
      id="game-pause-document"
      class="game-pause-document"
      role="document"
      tabindex="-1"
      bind:this={pauseDocument}
    >
      <p class="game-pause-kicker">{t("Case sealed")}</p>
      <h2 id="game-pause-heading" class="mt-2 font-serif text-3xl font-semibold tracking-[-0.025em] sm:text-4xl">
        {t("Case paused")}
      </h2>
      <p id="game-pause-description" class="mt-3 font-serif text-base italic leading-7">
        {pauseDescription(reason, offlinePlayers)}
      </p>

      <div class="game-pause-ledger">
        <span>{t("Connection ledger")}</span>
        <strong>{offlinePlayers.length === 0 ? t("All investigators present") : t("{count} absent", { count: offlinePlayers.length })}</strong>
      </div>

      <ul id="paused-player-list" class="noir-paused-player-list" aria-label={t("Offline players")}>
        {#each offlinePlayers as player (player.id)}
          <li><span aria-hidden="true"></span>{player.display_name}</li>
        {:else}
          <li class="noir-paused-player-list-empty">{t("No investigator currently marked offline.")}</li>
        {/each}
      </ul>

      <p class="game-pause-provenance">
        {t("No clues, actions, or Day advances are filed while the case is sealed.")}
      </p>

      {#if commandError}
        <div id="game-pause-command-error" class="game-pause-command-error" role="alert">
          <p>{t(commandError)}</p>
        </div>
      {/if}

      {#if canResume}
        <button
          id="resume-game"
          type="button"
          disabled={commandPending}
          onclick={onResume}
        >{commandPending ? t("Reopening case…") : t("Resume game")}</button>
      {:else}
        <p class="noir-pause-waiting">{t("The Chisel will reopen the case when every player is back.")}</p>
      {/if}
    </div>
  </div>
{/if}
