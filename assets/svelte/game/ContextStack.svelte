<script>
  let {
    selection = null,
    fieldSelection = null,
    suspectSelection = null,
    specialActorSelection = null,
    actionPrompt = null,
    origin = null,
    commandPending = false,
    commandError = null,
    commandStatus = false,
    connectionOnline = false,
    onConfirmMove = () => {},
    onCancelMove = () => {},
    onOpenFieldAction = () => {},
    onCancelField = () => {},
    onOpenSuspectAction = () => {},
    onCancelSuspect = () => {},
    onInteractSpecialActor = () => {},
    onCancelSpecialActor = () => {},
    onConfirmAction = () => {},
    onCancelAction = () => {},
  } = $props()

  let confirmationLabel = $derived(
    selection?.type === "place" ? "Confirm Placement" : "Confirm Move",
  )
  let cancelLabel = $derived(
    selection?.type === "place" ? "Cancel Placement" : "Cancel Move",
  )

  function fieldActionLabel(action) {
    return (
      {
        search_location: "Open Location Search",
        analyze: "Analyze Case",
        kickback: "Collect Kickback",
        bribe_officer: "Open Officer Bribe",
      }[action] ?? action.replaceAll("_", " ")
    )
  }
</script>

{#if selection || fieldSelection || suspectSelection || specialActorSelection || actionPrompt || commandError}
  <div id="context-stack" class="noir-context-stack">
    {#if commandPending && (selection || actionPrompt)}
      <p class="sr-only" role="status" aria-live="polite">Dispatching action</p>
    {/if}

    {#if fieldSelection}
      <article id="field-position-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">FIELD</div>
        <p class="noir-movement-slip-kicker">Current field position</p>
        <h3 class="noir-action-slip-title">{fieldSelection.location.name}</h3>
        <p class="noir-action-slip-description">
          D{fieldSelection.detective.seat} {fieldSelection.detective.display_name} · {fieldSelection.detective.actions_remaining} AP remaining
        </p>
        <p class="noir-movement-slip-districts">
          Choose one authorized desk or location action.
        </p>

        <div class="noir-field-slip-controls">
          {#each fieldSelection.actionTypes as action}
            <button
              id={`action-open-field-${action.replaceAll("_", "-")}`}
              type="button"
              class="noir-context-button noir-context-button-confirm"
              disabled={commandPending || !connectionOnline}
              onclick={() => onOpenFieldAction(fieldSelection, action)}
            >{fieldActionLabel(action)}</button>
          {/each}
          <button
            id="action-cancel-field"
            type="button"
            class="noir-context-button noir-context-button-dismiss"
            disabled={commandPending}
            onclick={() => onCancelField(fieldSelection)}
          >Close position</button>
        </div>
      </article>
    {/if}

    {#if suspectSelection}
      <article id="suspect-dossier-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">PERSON</div>
        <p class="noir-movement-slip-kicker">Authorized field lead</p>
        <h3 class="noir-action-slip-title">{suspectSelection.suspect.name}</h3>
        <p class="noir-action-slip-description">
          {suspectSelection.suspect.occupation ?? "Person of interest"} · {suspectSelection.location.name}
        </p>
        <p class="noir-movement-slip-districts">
          Open the matching folio before spending an action.
        </p>

        <div class="noir-suspect-slip-controls">
          {#if suspectSelection.canSearch}
            <button
              id="action-open-suspect-search"
              type="button"
              class="noir-context-button noir-context-button-confirm"
              disabled={commandPending || !connectionOnline}
              onclick={() => onOpenSuspectAction(suspectSelection, "search_suspect")}
            >Open Search</button>
          {/if}
          {#if suspectSelection.canInterrogate}
            <button
              id="action-open-suspect-question"
              type="button"
              class="noir-context-button noir-context-button-confirm"
              disabled={commandPending || !connectionOnline}
              onclick={() => onOpenSuspectAction(suspectSelection, "interrogate")}
            >Open Question</button>
          {/if}
          <button
            id="action-cancel-suspect"
            type="button"
            class="noir-context-button noir-context-button-dismiss"
            disabled={commandPending}
            onclick={() => onCancelSuspect(suspectSelection)}
          >Close file</button>
        </div>
      </article>
    {/if}

    {#if specialActorSelection}
      <article id="special-actor-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">
          {specialActorSelection.options.some((option) => option.choice_group)
            ? "DECISION"
            : "SPECIAL"}
        </div>
        <p class="noir-movement-slip-kicker">Case-specific interaction</p>
        <h3 class="noir-action-slip-title">{specialActorSelection.actor.name}</h3>
        <p class="noir-action-slip-description">
          {specialActorSelection.actor.role} · {specialActorSelection.location.name}
        </p>
        <p class="noir-movement-slip-districts">
          The server will resolve the selected cost and any private result.
        </p>
        {#if specialActorSelection.options.some((option) => option.choice_group)}
          <p id="special-actor-choice-warning" class="noir-action-slip-description">
            Choose one marked approach. Filing it permanently closes the alternatives.
          </p>
        {/if}

        <div class="noir-special-actor-options">
          {#each specialActorSelection.options as option}
            <button
              id={`action-special-actor-${option.id}`}
              type="button"
              class="noir-context-button noir-context-button-confirm"
              disabled={commandPending || !connectionOnline}
              onclick={() => onInteractSpecialActor(specialActorSelection, option)}
            >
              <span>{option.label}</span>
              <small>
                {option.choice_group ? "Exclusive route · " : ""}{option.action_cost} AP · ${option.scratch_cost}
              </small>
            </button>
          {/each}
          <button
            id="action-cancel-special-actor"
            type="button"
            class="noir-context-button noir-context-button-dismiss"
            disabled={commandPending}
            onclick={() => onCancelSpecialActor(specialActorSelection)}
          >Close contact</button>
        </div>
      </article>
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
