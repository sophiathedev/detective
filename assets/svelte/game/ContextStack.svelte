<script>
  let {
    selection = null,
    actionPrompt = null,
    origin = null,
    commandPending = false,
    commandError = null,
    commandStatus = false,
    connectionOnline = false,
    onConfirmMove = () => {},
    onCancelMove = () => {},
    onConfirmAction = () => {},
    onCancelAction = () => {},
  } = $props()

  let confirmationLabel = $derived(
    selection?.type === "place" ? "Confirm Placement" : "Confirm Move",
  )
  let cancelLabel = $derived(
    selection?.type === "place" ? "Cancel Placement" : "Cancel Move",
  )
</script>

{#if selection || actionPrompt || commandError}
  <div id="context-stack" class="noir-context-stack">
    {#if commandPending && (selection || actionPrompt)}
      <p class="sr-only" role="status" aria-live="polite">Dispatching action</p>
    {/if}

    {#if selection}
      <article id="movement-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">
          {selection.type === "place" ? "PLACE" : "MOVE"}
        </div>
        <p class="noir-movement-slip-kicker">
          {selection.type === "place" ? "Free initial placement" : "Proposed destination"}
        </p>

        <div class="noir-movement-slip-route">
          <div>
            <span>From</span>
            <strong>{origin?.name ?? "Off board"}</strong>
          </div>
          <span aria-hidden="true">→</span>
          <div>
            <span>To</span>
            <strong>{selection.location.name}</strong>
          </div>
        </div>

        <p class="noir-movement-slip-districts">
          Filed districts · {selection.location.district_ids?.join(" / ") ?? "unfiled"}
        </p>

        <div class="noir-movement-slip-controls">
          <button
            id="action-cancel-movement"
            type="button"
            class="noir-context-button"
            disabled={commandPending}
            onclick={() => onCancelMove(selection)}
          >{cancelLabel}</button>
          <button
            id="action-confirm-movement"
            type="button"
            class="noir-context-button noir-context-button-confirm"
            disabled={commandPending || !connectionOnline}
            onclick={() => onConfirmMove(selection)}
          >{commandPending ? "Dispatching car" : confirmationLabel}</button>
        </div>
      </article>
    {/if}

    {#if actionPrompt}
      <article id="action-confirmation-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">{actionPrompt.stamp}</div>
        <p class="noir-movement-slip-kicker">{actionPrompt.kicker}</p>
        <h3 class="noir-action-slip-title">{actionPrompt.title}</h3>
        <p class="noir-action-slip-description">{actionPrompt.description}</p>
        {#if origin}
          <p class="noir-movement-slip-districts">Filed at {origin.name}</p>
        {/if}

        <div class="noir-movement-slip-controls">
          <button
            id="action-cancel-confirmation"
            type="button"
            class="noir-context-button"
            disabled={commandPending}
            onclick={() => onCancelAction(actionPrompt)}
          >Keep planning</button>
          <button
            id="action-confirm-immediate"
            type="button"
            class="noir-context-button noir-context-button-confirm"
            disabled={commandPending || !connectionOnline}
            onclick={() => onConfirmAction(actionPrompt)}
          >{commandPending ? "Filing action" : actionPrompt.confirmLabel}</button>
        </div>
      </article>
    {/if}

    {#if commandError}
      <p
        id="game-command-message"
        class:noir-command-message-status={commandStatus}
        class="noir-command-message noir-paper-sheet"
        role={commandStatus ? "status" : "alert"}
        aria-live={commandStatus ? "polite" : "assertive"}
      >
        {commandError}
      </p>
    {/if}
  </div>
{/if}
