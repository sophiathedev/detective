<script>
  let {
    availableActions = [],
    activeAction = null,
    commandPending = false,
    connectionOnline = false,
    onChooseAction = () => {},
    onAction = () => {},
    onOpenCasebook = () => {},
  } = $props()

  const actionDefinitions = [
    { id: "place", label: "Place", mode: true },
    { id: "move", label: "Move", mode: true },
    { id: "search_location", label: "Search Location" },
    { id: "search_suspect", label: "Search Suspect" },
    { id: "interrogate", label: "Question Suspect" },
    { id: "analyze", label: "Analyze" },
    { id: "kickback", label: "Kickback" },
    { id: "skip_free_question", label: "Decline Free Question" },
    { id: "accuse", label: "Accuse", danger: true },
    { id: "submit_final_guess", label: "Seal Final Guess", danger: true },
    { id: "end_turn", label: "End Turn", danger: true },
  ]

  let availableActionSet = $derived(new Set(availableActions ?? []))
  let projectedActions = $derived(
    actionDefinitions.filter((action) => availableActionSet.has(action.id)),
  )

  function dispatch(action) {
    if (commandPending || !connectionOnline) return
    if (action.mode) onChooseAction(action.id)
    else onAction(action.id)
  }
</script>

<div id="action-rail" class="noir-action-rail noir-wood-frame">
  <div class="noir-action-rail-ledger" aria-hidden="true">
    <span>Dispatch</span>
    <strong>{connectionOnline ? "Line open" : "Line closed"}</strong>
  </div>

  <div class="noir-action-key-row">
    {#each projectedActions as action (action.id)}
      <button
        id={`action-${action.id.replaceAll("_", "-")}`}
        type="button"
        class:noir-action-key-active={action.mode && activeAction === action.id}
        class:noir-action-key-danger={action.danger}
        class="noir-action-key"
        aria-pressed={action.mode ? activeAction === action.id : undefined}
        disabled={commandPending || !connectionOnline}
        onclick={() => dispatch(action)}
      >
        {action.label}
      </button>
    {/each}

    <button
      id="action-open-casebook"
      type="button"
      class="noir-action-key noir-action-key-casebook"
      onclick={onOpenCasebook}
    >
      Casebook
    </button>
  </div>
</div>
