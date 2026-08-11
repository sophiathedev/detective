<script>
  import GameBoard from "./GameBoard.svelte"
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let {
    locations = [],
    detectives = [],
    actionableDetectiveId = null,
    detectiveActionTypes = [],
    selectedDetectiveId = null,
    detectiveInteractionsDisabled = false,
    suspects = [],
    searchableSuspectIds = [],
    interrogatableSuspectIds = [],
    selectedSuspectId = null,
    suspectInteractionsDisabled = false,
    specialActors = [],
    interactableSpecialActorIds = [],
    selectedSpecialActorId = null,
    specialActorInteractionsDisabled = false,
    caseCardSlots = [],
    inspectableCaseCardCodes = [],
    selectedCaseCardCode = null,
    legalLocationIds = [],
    selectedLocationId = null,
    pendingLocationId = null,
    lastTravel = null,
    disabled = false,
    status = "",
    onSelect = () => {},
    onSelectDetective = () => {},
    onSelectSuspect = () => {},
    onSelectSpecialActor = () => {},
    onSelectCaseCard = () => {},
  } = $props()

  const zoomLevels = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.5]
  let zoomIndex = $state(0)
  let zoom = $derived(zoomLevels[zoomIndex])
</script>

<section id="map-stage" class="noir-map-stage" aria-labelledby="game-map-title">
  <div class="noir-map-hardware" aria-hidden="true">
    <span class="noir-map-corner noir-map-corner-nw"></span>
    <span class="noir-map-corner noir-map-corner-ne"></span>
    <span class="noir-map-corner noir-map-corner-sw"></span>
    <span class="noir-map-corner noir-map-corner-se"></span>
  </div>

  <div
    id="map-stage-status"
    class="noir-map-status"
    aria-live="polite"
    aria-busy={pendingLocationId !== null}
  >
    {status}
  </div>

  <div class="noir-map-zoom-controls" aria-label={t("Map zoom controls")}>
    <button
      type="button"
      aria-label={t("Zoom out")}
      disabled={zoomIndex === 0}
      onclick={() => (zoomIndex -= 1)}
    >−</button>
    <button type="button" aria-label={t("Reset map zoom")} onclick={() => (zoomIndex = 0)}>
      {Math.round(zoom * 100)}%
    </button>
    <button
      type="button"
      aria-label={t("Zoom in")}
      disabled={zoomIndex === zoomLevels.length - 1}
      onclick={() => (zoomIndex += 1)}
    >+</button>
  </div>

  <div class="noir-map-pan-region">
    <div id="map-zoom-plane" data-zoom={zoom} style={`width: ${zoom * 100}%;`}>
      <GameBoard
        {locations}
        {detectives}
        {actionableDetectiveId}
        {detectiveActionTypes}
        {selectedDetectiveId}
        {detectiveInteractionsDisabled}
        {suspects}
        {searchableSuspectIds}
        {interrogatableSuspectIds}
        {selectedSuspectId}
        {suspectInteractionsDisabled}
        {specialActors}
        {interactableSpecialActorIds}
        {selectedSpecialActorId}
        {specialActorInteractionsDisabled}
        {caseCardSlots}
        {inspectableCaseCardCodes}
        {selectedCaseCardCode}
        {zoom}
        legalLocationIds={disabled ? [] : legalLocationIds}
        {selectedLocationId}
        {pendingLocationId}
        {lastTravel}
        {disabled}
        {onSelect}
        {onSelectDetective}
        {onSelectSuspect}
        {onSelectSpecialActor}
        {onSelectCaseCard}
      />
    </div>
  </div>

  <p id="board-attribution" class="noir-board-attribution">
    {t("Board artwork © Van Ryder Games / Vincent Dutrait. Unofficial non-commercial fan project; not affiliated with or endorsed by the publisher.")}
  </p>
</section>
