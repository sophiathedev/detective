<script>
  import { onDestroy } from "svelte"

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
      <p class="game-pause-kicker">Case sealed</p>
      <h2 id="game-pause-heading" class="mt-2 font-serif text-3xl font-semibold tracking-[-0.025em] sm:text-4xl">
        Case paused
      </h2>
      <p id="game-pause-description" class="mt-3 font-serif text-base italic leading-7">
        {reason ?? "Waiting for every investigator to return."}
      </p>

      <div class="game-pause-ledger">
        <span>Connection ledger</span>
        <strong>{offlinePlayers.length === 0 ? "All investigators present" : `${offlinePlayers.length} absent`}</strong>
      </div>

      <ul id="paused-player-list" class="noir-paused-player-list" aria-label="Offline players">
        {#each offlinePlayers as player (player.id)}
          <li><span aria-hidden="true"></span>{player.display_name}</li>
        {:else}
          <li class="noir-paused-player-list-empty">No investigator currently marked offline.</li>
        {/each}
      </ul>

      <p class="game-pause-provenance">
        Presence reports connection only. Membership, role, and resume authority remain server-owned.
      </p>

      {#if commandError}
        <div id="game-pause-command-error" class="game-pause-command-error" role="alert">
          <p>{commandError}</p>
        </div>
      {/if}

      {#if canResume}
        <button
          id="resume-game"
          type="button"
          disabled={commandPending}
          onclick={onResume}
        >{commandPending ? "Reopening case…" : "Resume game"}</button>
      {:else}
        <p class="noir-pause-waiting">Waiting for the Chisel to reopen the case.</p>
      {/if}
    </div>
  </div>
{/if}
