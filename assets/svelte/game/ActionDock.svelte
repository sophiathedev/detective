<script>
  let {
    availableActions = [],
    selection = null,
    origin = null,
    commandPending = false,
    commandError = null,
    connectionOnline = false,
    onConfirmMove = () => {},
    onCancelMove = () => {},
    onAction = () => {},
  } = $props()

  const actionDefinitions = [
    { id: "search_location", label: "Search Location", tone: "field" },
    { id: "search_suspect", label: "Search Suspect", tone: "field" },
    { id: "interrogate", label: "Question Suspect", tone: "field" },
    { id: "analyze", label: "Analyze", tone: "field" },
    { id: "kickback", label: "Kickback", tone: "field" },
    { id: "skip_free_question", label: "Decline Free Question", tone: "quiet" },
    { id: "accuse", label: "Accuse", tone: "danger" },
    { id: "submit_final_guess", label: "Seal Final Guess", tone: "danger" },
    { id: "end_turn", label: "End Turn", tone: "danger" },
  ]

  let availableActionSet = $derived(new Set(availableActions ?? []))
  let projectedActions = $derived(
    actionDefinitions.filter((action) => availableActionSet.has(action.id)),
  )
  let movementAvailable = $derived(
    availableActionSet.has("place") || availableActionSet.has("move"),
  )
  let confirmationLabel = $derived(
    selection?.type === "place" ? "Confirm Placement" : "Confirm Move",
  )
  let cancelLabel = $derived(
    selection?.type === "place" ? "Cancel Placement" : "Cancel Move",
  )
</script>

<section id="action-dock" class="action-dock" aria-labelledby="action-dock-heading">
  <div class="action-dock-heading-row">
    <div>
      <p class="action-dock-kicker">Dispatch desk · server authority</p>
      <h3 id="action-dock-heading" class="action-dock-heading">Field actions</h3>
    </div>
    <span class:action-dock-connection-online={connectionOnline} class="action-dock-connection">
      {connectionOnline ? "Line open" : "Line closed"}
    </span>
  </div>

  {#if selection}
    <article id="movement-slip" class="movement-slip" aria-live="polite">
      <div class="movement-slip-stamp" aria-hidden="true">
        {selection.type === "place" ? "PLACE" : "MOVE"}
      </div>
      <p class="movement-slip-label">Proposed destination</p>
      <div class="movement-slip-route">
        <div>
          <span>From</span>
          <strong>{origin?.name ?? "Off board"}</strong>
        </div>
        <span class="movement-slip-arrow" aria-hidden="true">→</span>
        <div>
          <span>To</span>
          <strong>{selection.location.name}</strong>
        </div>
      </div>
      <p class="movement-slip-districts">
        Filed districts · {selection.location.district_ids?.join(" / ") ?? "unfiled"}
      </p>

      <div class="movement-slip-controls">
        <button
          id="action-cancel-movement"
          type="button"
          class="action-dock-button action-dock-button-quiet"
          disabled={commandPending}
          onclick={() => onCancelMove(selection)}
        >{cancelLabel}</button>
        <button
          id="action-confirm-movement"
          type="button"
          class="action-dock-button action-dock-button-confirm"
          disabled={commandPending || !connectionOnline}
          onclick={() => onConfirmMove(selection)}
        >{commandPending ? "Dispatching car" : confirmationLabel}</button>
      </div>
    </article>
  {:else if movementAvailable}
    <p id="movement-selection-prompt" class="action-dock-prompt">
      Select a red-ringed destination on the map. No command is sent until you confirm the dispatch slip.
    </p>
  {/if}

  {#if projectedActions.length > 0}
    <div id="projected-actions" class="action-dock-actions">
      {#each projectedActions as action (action.id)}
        <button
          id={`action-${action.id.replaceAll("_", "-")}`}
          type="button"
          class:action-dock-button-danger={action.tone === "danger"}
          class:action-dock-button-quiet={action.tone === "quiet"}
          class="action-dock-button action-dock-button-field"
          disabled={commandPending || !connectionOnline}
          onclick={() => onAction(action.id)}
        >{action.label}</button>
      {/each}
    </div>
  {:else if !movementAvailable}
    <p id="no-projected-actions" class="action-dock-prompt">No field action is authorized in the current phase.</p>
  {/if}

  {#if commandError}
    <p id="action-dock-error" class="action-dock-error" role="alert">{commandError}</p>
  {/if}
</section>
