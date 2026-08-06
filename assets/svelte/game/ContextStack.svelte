<script>
  import { useI18n } from "../i18n"

  const { t } = useI18n()

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
    selection?.type === "place" ? t("Confirm Start") : t("Confirm Move"),
  )
  let cancelLabel = $derived(
    selection?.type === "place" ? t("Cancel Start") : t("Cancel Move"),
  )

  function fieldActionLabel(action) {
    return (
      {
        search_location: t("Open Location Search"),
        analyze: t("Analyze Case"),
        kickback: t("Collect Kickback"),
        bribe_officer: t("Open Officer Bribe"),
      }[action] ?? action.replaceAll("_", " ")
    )
  }
</script>

{#if selection || fieldSelection || suspectSelection || specialActorSelection || actionPrompt || commandError}
  <div id="context-stack" class="noir-context-stack">
    {#if commandPending && (selection || actionPrompt)}
      <p class="sr-only" role="status" aria-live="polite">{t("Dispatching action")}</p>
    {/if}

    {#if fieldSelection}
      <article id="field-position-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">{t("FIELD")}</div>
        <p class="noir-movement-slip-kicker">{t("Current field position")}</p>
        <h3 class="noir-action-slip-title">{fieldSelection.location.name}</h3>
        <p class="noir-action-slip-description">
          {t("D{seat} {name} · {actions} AP remaining", { seat: fieldSelection.detective.seat, name: fieldSelection.detective.display_name, actions: fieldSelection.detective.actions_remaining })}
        </p>
        <p class="noir-movement-slip-districts">
          {t("Choose one authorized desk or location action.")}
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
          >{t("Close position")}</button>
        </div>
      </article>
    {/if}

    {#if suspectSelection}
      <article id="suspect-dossier-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">{t("PERSON")}</div>
        <p class="noir-movement-slip-kicker">{t("Authorized field lead")}</p>
        <h3 class="noir-action-slip-title">{suspectSelection.suspect.name}</h3>
        <p class="noir-action-slip-description">
          {t("{occupation} · {location}", { occupation: suspectSelection.suspect.occupation ?? t("Person of interest"), location: suspectSelection.location.name })}
        </p>
        <p class="noir-movement-slip-districts">
          {t("Open the matching folio before spending an action.")}
        </p>

        <div class="noir-suspect-slip-controls">
          {#if suspectSelection.canSearch}
            <button
              id="action-open-suspect-search"
              type="button"
              class="noir-context-button noir-context-button-confirm"
              disabled={commandPending || !connectionOnline}
              onclick={() => onOpenSuspectAction(suspectSelection, "search_suspect")}
            >{t("Open Search")}</button>
          {/if}
          {#if suspectSelection.canInterrogate}
            <button
              id="action-open-suspect-question"
              type="button"
              class="noir-context-button noir-context-button-confirm"
              disabled={commandPending || !connectionOnline}
              onclick={() => onOpenSuspectAction(suspectSelection, "interrogate")}
            >{t("Open Question")}</button>
          {/if}
          <button
            id="action-cancel-suspect"
            type="button"
            class="noir-context-button noir-context-button-dismiss"
            disabled={commandPending}
            onclick={() => onCancelSuspect(suspectSelection)}
          >{t("Close file")}</button>
        </div>
      </article>
    {/if}

    {#if specialActorSelection}
      <article id="special-actor-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">
          {specialActorSelection.options.some((option) => option.choice_group)
            ? t("DECISION")
            : t("SPECIAL")}
        </div>
        <p class="noir-movement-slip-kicker">{t("Case-specific interaction")}</p>
        <h3 class="noir-action-slip-title">{specialActorSelection.actor.name}</h3>
        <p class="noir-action-slip-description">
          {specialActorSelection.actor.role} · {specialActorSelection.location.name}
        </p>
        <p class="noir-movement-slip-districts">
          {t("The server will resolve the selected cost and any private result.")}
        </p>
        {#if specialActorSelection.options.some((option) => option.choice_group)}
          <p id="special-actor-choice-warning" class="noir-action-slip-description">
            {t("Choose one marked approach. Filing it permanently closes the alternatives.")}
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
              <span>{t(option.label)}</span>
              <small>
                {option.choice_group ? t("Exclusive route · ") : ""}{t("{actions} AP · ${scratch}", { actions: option.action_cost, scratch: option.scratch_cost })}
              </small>
            </button>
          {/each}
          <button
            id="action-cancel-special-actor"
            type="button"
            class="noir-context-button noir-context-button-dismiss"
            disabled={commandPending}
            onclick={() => onCancelSpecialActor(specialActorSelection)}
          >{t("Close contact")}</button>
        </div>
      </article>
    {/if}

    {#if selection}
      <article id="movement-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">
          {selection.type === "place" ? t("START") : t("MOVE")}
        </div>
        <p class="noir-movement-slip-kicker">
          {selection.type === "place" ? t("Initial dispatch point") : t("Proposed destination")}
        </p>

        <div class="noir-movement-slip-route">
          <div>
            <span>{t("From")}</span>
            <strong>{origin?.name ?? t("Off board")}</strong>
          </div>
          <span aria-hidden="true">→</span>
          <div>
            <span>{t("To")}</span>
            <strong>{selection.location.name}</strong>
          </div>
        </div>

        <p class="noir-movement-slip-districts">
          {t("Filed districts · {districts}", { districts: selection.location.district_ids?.join(" / ") ?? t("unfiled") })}
          <strong class="noir-movement-slip-cost">
            {selection.type === "place" ? t("No AP cost") : t("Movement cost · 1 AP")}
          </strong>
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
          >{commandPending ? t("Dispatching car") : confirmationLabel}</button>
        </div>
      </article>
    {/if}

    {#if actionPrompt}
      <article id="action-confirmation-slip" class="noir-movement-slip noir-paper-sheet" aria-live="polite">
        <div class="noir-movement-slip-stamp" aria-hidden="true">{t(actionPrompt.stamp)}</div>
        <p class="noir-movement-slip-kicker">{t(actionPrompt.kicker)}</p>
        <h3 class="noir-action-slip-title">{t(actionPrompt.title)}</h3>
        <p class="noir-action-slip-description">{t(actionPrompt.description)}</p>
        {#if origin}
          <p class="noir-movement-slip-districts">{t("Filed at {location}", { location: origin.name })}</p>
        {/if}

        <div class="noir-movement-slip-controls">
          <button
            id="action-cancel-confirmation"
            type="button"
            class="noir-context-button"
            disabled={commandPending}
            onclick={() => onCancelAction(actionPrompt)}
          >{t("Keep planning")}</button>
          <button
            id="action-confirm-immediate"
            type="button"
            class="noir-context-button noir-context-button-confirm"
            disabled={commandPending || !connectionOnline}
            onclick={() => onConfirmAction(actionPrompt)}
          >{commandPending ? t("Filing action") : t(actionPrompt.confirmLabel)}</button>
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
        {t(commandError)}
      </p>
    {/if}
  </div>
{/if}
