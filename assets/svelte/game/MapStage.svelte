<script>
  import GameBoard from "./GameBoard.svelte"

  let {
    locations = [],
    detectives = [],
    caseCardSlots = [],
    legalLocationIds = [],
    selectedLocationId = null,
    pendingLocationId = null,
    lastTravel = null,
    disabled = false,
    status = "",
    onSelect = () => {},
  } = $props()

  const zoomLevels = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.5]
  let zoomIndex = $state(0)
  let zoom = $derived(zoomLevels[zoomIndex])
</script>

<section id="map-stage" class="noir-map-stage" aria-labelledby="game-map-title">
  <div
    id="map-stage-status"
    class="noir-map-status"
    aria-live="polite"
    aria-busy={pendingLocationId !== null}
  >
    {status}
  </div>

  <div class="noir-map-zoom-controls" aria-label="Map zoom controls">
    <button
      type="button"
      aria-label="Zoom out"
      disabled={zoomIndex === 0}
      onclick={() => (zoomIndex -= 1)}
    >−</button>
    <button type="button" aria-label="Reset map zoom" onclick={() => (zoomIndex = 0)}>
      {Math.round(zoom * 100)}%
    </button>
    <button
      type="button"
      aria-label="Zoom in"
      disabled={zoomIndex === zoomLevels.length - 1}
      onclick={() => (zoomIndex += 1)}
    >+</button>
  </div>

  <div class="noir-map-pan-region">
    <div id="map-zoom-plane" data-zoom={zoom} style={`width: ${zoom * 100}%;`}>
      <GameBoard
        {locations}
        {detectives}
        {caseCardSlots}
        legalLocationIds={disabled ? [] : legalLocationIds}
        {selectedLocationId}
        {pendingLocationId}
        {lastTravel}
        {disabled}
        {onSelect}
      />
    </div>
  </div>

  <p id="board-attribution" class="noir-board-attribution">
    Board artwork © Van Ryder Games / Vincent Dutrait. Unofficial non-commercial fan project; not affiliated with or endorsed by the publisher.
  </p>
</section>
