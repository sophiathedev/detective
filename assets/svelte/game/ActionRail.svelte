<script>
  import ActionGlyph from "./ActionGlyph.svelte"
  import { useI18n } from "../i18n"

  const { t } = useI18n()

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
    { id: "place", label: "Choose Start", mode: true },
    { id: "move", label: "Move", mode: true },
    { id: "search_location", label: "Search Location" },
    { id: "search_suspect", label: "Search Suspect" },
    { id: "interrogate", label: "Question Suspect" },
    { id: "analyze", label: "Analyze" },
    { id: "kickback", label: "Kickback" },
    { id: "bribe_detective", label: "Bribe Detective" },
    { id: "bribe_officer", label: "Bribe Officer" },
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
    <span>{t("Dispatch")}</span>
    <strong>{connectionOnline ? t("Line open") : t("Line closed")}</strong>
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
        <span class="noir-action-glyph" aria-hidden="true">
          <ActionGlyph name={action.id} />
        </span>
        <span class="noir-action-key-label">{t(action.label)}</span>
      </button>
    {/each}

    <button
      id="action-open-casebook"
      type="button"
      class="noir-action-key noir-action-key-casebook"
      onclick={onOpenCasebook}
    >
      <span class="noir-action-glyph" aria-hidden="true">
        <ActionGlyph name="casebook" />
      </span>
      <span class="noir-action-key-label">{t("Casebook")}</span>
    </button>
  </div>
</div>
