<script>
  let {
    locations = [],
    detectives = [],
    legalLocationIds = [],
    selectedLocationId = null,
    pendingLocationId = null,
    lastTravel = null,
    disabled = false,
    onSelect = () => {},
  } = $props()

  let legalIds = $derived(new Set(disabled ? [] : legalLocationIds))
  let legalLocations = $derived(locations.filter((location) => legalIds.has(location.id)))
  let travelPath = $derived.by(() => {
    if (!lastTravel?.from_location_id || !lastTravel?.location_id) return null

    const from = locations.find((location) => location.id === lastTravel.from_location_id)
    const destination = locations.find((location) => location.id === lastTravel.location_id)

    return from && destination ? { from, destination, key: lastTravel.key } : null
  })

  function select(event, location) {
    if (!legalIds.has(location.id)) return
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return
    if (event.type === "keydown") event.preventDefault()
    onSelect(location)
  }

  function markerFill(location) {
    if (location.type === "police_station") return "#243c48"
    if (location.type === "mob_joint") return "#7a302c"
    return "#e4d5b4"
  }

  function tokenColor(seat) {
    return ["#28485c", "#724438", "#3f5d44", "#6b5535"][seat - 1] ?? "#4d4439"
  }
</script>

<div class="game-board-frame">
  <svg
    id="game-map"
    data-testid="game-map"
    class="game-map-board aspect-[1000/636] w-full select-none border border-[#6e5c48] bg-[#c9b998]"
    viewBox="0 0 1000 636"
    preserveAspectRatio="xMidYMid meet"
    aria-labelledby="game-map-title game-map-description"
  >
    <title id="game-map-title">Detective: City of Angels investigation board</title>
    <desc id="game-map-description">
      Official game board with server-authorized location hotspots and Detective tokens.
    </desc>
    <defs>
      <filter id="board-ink">
        <feColorMatrix type="saturate" values="0.86" />
        <feComponentTransfer>
          <feFuncR type="linear" slope="0.96" intercept="0.02" />
          <feFuncG type="linear" slope="0.94" intercept="0.025" />
          <feFuncB type="linear" slope="0.9" intercept="0.035" />
        </feComponentTransfer>
      </filter>
      <filter id="token-shadow" x="-80%" y="-80%" width="260%" height="260%">
        <feDropShadow dx="0" dy="5" stdDeviation="4" flood-color="#211810" flood-opacity="0.66" />
      </filter>
    </defs>

    <image
      data-testid="official-board-image"
      href="/images/maps/dcoa/game-board-final.png"
      width="1000"
      height="636"
      filter="url(#board-ink)"
    />
    <rect width="1000" height="636" fill="#392619" opacity="0.045" aria-hidden="true" />

    {#if travelPath}
      {#key travelPath.key}
        <g id="latest-travel-trace" class="map-travel-trace" aria-hidden="true">
          <line
            x1={travelPath.from.x * 1000}
            y1={travelPath.from.y * 636}
            x2={travelPath.destination.x * 1000}
            y2={travelPath.destination.y * 636}
            pathLength="1"
            class="map-travel-line"
            vector-effect="non-scaling-stroke"
          />
          <circle
            cx={travelPath.destination.x * 1000}
            cy={travelPath.destination.y * 636}
            r="24"
            class="map-arrival-pulse"
            vector-effect="non-scaling-stroke"
          />
        </g>
      {/key}
    {/if}

    <g id="map-locations">
      {#each locations as location}
        {@const legal = legalIds.has(location.id)}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <g
          id={`map-location-${location.id}`}
          data-testid={`map-hotspot-${location.id}`}
          data-selected={selectedLocationId === location.id}
          transform={`translate(${location.x * 1000} ${location.y * 636})`}
          class={`map-location-marker ${legal ? "map-location-legal cursor-pointer" : "cursor-default"} ${pendingLocationId === location.id ? "map-location-pending" : ""}`}
          role={legal ? "button" : undefined}
          tabindex={legal ? "0" : undefined}
          focusable={legal ? "true" : "false"}
          aria-label={legal ? `Select ${location.name} on the map` : undefined}
          aria-busy={pendingLocationId === location.id ? "true" : undefined}
          onclick={(event) => select(event, location)}
          onkeydown={(event) => select(event, location)}
        >
          <title>{location.name}</title>
          <circle class="map-hotspot-target" r="22" fill="transparent" />
          {#if legal}
            <circle
              class="map-legal-ring"
              r="25"
              fill="none"
              stroke="#c94f3e"
              stroke-width="4"
              vector-effect="non-scaling-stroke"
            />
          {/if}
          {#if selectedLocationId === location.id || pendingLocationId === location.id}
            <circle
              r="12"
              fill={markerFill(location)}
              stroke={pendingLocationId === location.id ? "#fff0cf" : "#f6ead0"}
              stroke-width="4"
              vector-effect="non-scaling-stroke"
            />
            <text
              y="4"
              text-anchor="middle"
              fill="#fff0d6"
              stroke="#2b2018"
              stroke-width="2"
              paint-order="stroke"
              font-family="IBM Plex Mono, monospace"
              font-size="10"
              font-weight="600"
            >{location.id}</text>
          {/if}
        </g>
      {/each}
    </g>

    <g id="detective-tokens" filter="url(#token-shadow)">
      {#each detectives as detective}
        {@const tokenLocation = locations.find((location) => location.id === detective.location_id)}
        {#if tokenLocation}
          <g
            id={`detective-map-token-${detective.id}`}
            class={`map-detective-token ${lastTravel?.player_id === detective.id ? "map-detective-token-active" : ""}`}
            style={`transform: translate(${tokenLocation.x * 1000 + (detective.seat - 1) * 11}px, ${tokenLocation.y * 636 - 16}px);`}
            aria-label={`${detective.display_name} at ${tokenLocation.name}`}
          >
            <path
              d="M0-18 15-8 12 14 0 22-12 14-15-8Z"
              fill={tokenColor(detective.seat)}
              stroke="#f2e4c8"
              stroke-width="3"
              vector-effect="non-scaling-stroke"
            />
            <text
              y="5"
              text-anchor="middle"
              fill="#f8ecd2"
              font-family="IBM Plex Mono, monospace"
              font-size="12"
              font-weight="600"
            >D{detective.seat}</text>
          </g>
        {/if}
      {/each}
    </g>
  </svg>

  <nav
    id="legal-map-destinations"
    class="border-x border-b border-[#6e5c48] bg-[#d2c19f] px-3 py-2"
    aria-label="Legal map destinations"
  >
    {#if legalLocations.length > 0}
      <div class="flex gap-2 overflow-x-auto pb-1">
        {#each legalLocations as location}
          <button
            id={`map-destination-${location.id}`}
            type="button"
            data-location-id={location.id}
            aria-controls="game-map"
            class="min-h-11 shrink-0 cursor-pointer border border-[#7b6249] bg-[#eadcbd] px-3 font-mono text-[10px] font-semibold uppercase tracking-[0.06em] text-[#3e2c20] transition hover:border-[#973b32] hover:bg-[#f4e8ce] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#8e342d]"
            aria-pressed={selectedLocationId === location.id}
            onclick={(event) => select(event, location)}
          >
            Choose {location.name}
          </button>
        {/each}
      </div>
    {:else}
      <p class="font-mono text-[9px] uppercase tracking-[0.08em] text-[#765f48]">
        No map destination is available for this player.
      </p>
    {/if}
  </nav>
</div>
