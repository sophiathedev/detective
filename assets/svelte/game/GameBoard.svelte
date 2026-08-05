<script>
  import CaseCardRail from "./CaseCardRail.svelte"

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
    caseCardSlots = [],
    legalLocationIds = [],
    selectedLocationId = null,
    pendingLocationId = null,
    lastTravel = null,
    disabled = false,
    onSelect = () => {},
    onSelectDetective = () => {},
    onSelectSuspect = () => {},
  } = $props()

  let legalIds = $derived(new Set(disabled ? [] : legalLocationIds))
  let searchableIds = $derived(
    new Set(disabled || suspectInteractionsDisabled ? [] : searchableSuspectIds),
  )
  let interrogatableIds = $derived(
    new Set(disabled || suspectInteractionsDisabled ? [] : interrogatableSuspectIds),
  )
  let availableDetectiveActions = $derived(
    disabled || detectiveInteractionsDisabled ? [] : detectiveActionTypes,
  )
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

  function detectiveActionLabel(action) {
    return (
      {
        search_location: "search location",
        analyze: "analyze evidence",
        kickback: "collect kickback",
        bribe_officer: "bribe officer",
      }[action] ?? action.replaceAll("_", " ")
    )
  }

  function detectiveLabel(detective, location, actions) {
    const identity = `${detective.display_name} at ${location.name}`
    return actions.length > 0
      ? `${identity}. Available actions: ${actions.map(detectiveActionLabel).join(", ")}.`
      : identity
  }

  function selectDetectiveToken(event, detective, actions) {
    if (actions.length === 0) return
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return
    if (event.type === "keydown") event.preventDefault()
    onSelectDetective(detective)
  }

  function suspectInitials(name) {
    return name
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part[0] ?? "")
      .join("")
      .toUpperCase()
  }

  function suspectActions(suspect) {
    return [
      searchableIds.has(suspect.id) ? "search" : null,
      interrogatableIds.has(suspect.id) ? "question" : null,
    ].filter(Boolean)
  }

  function suspectLabel(suspect, location, actions) {
    const identity = `${suspect.name}, ${suspect.occupation}, at ${location.name}`
    return actions.length > 0
      ? `${identity}. Available actions: ${actions.join(" and ")}.`
      : identity
  }

  function selectSuspectStandee(event, suspect, actions) {
    if (actions.length === 0) return
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return
    if (event.type === "keydown") event.preventDefault()
    onSelectSuspect(suspect)
  }

  function suspectPlacement(suspect) {
    const location = locations.find((candidate) => candidate.id === suspect.location_id)
    if (!location) return null

    const colocated = suspects.filter((candidate) => candidate.location_id === suspect.location_id)
    const index = colocated.findIndex((candidate) => candidate.id === suspect.id)
    const offset = (index - (colocated.length - 1) / 2) * 20
    const sharesLocationWithDetective = detectives.some(
      (detective) => detective.location_id === suspect.location_id,
    )

    return {
      location,
      x: location.x * 1000 + offset - (sharesLocationWithDetective ? 28 : 0),
      y: location.y * 636 + (sharesLocationWithDetective ? 42 : 24),
    }
  }
</script>

<div class="game-board-frame">
  <svg
    id="game-map"
    data-testid="game-map"
    class="game-map-board aspect-[1000/636] w-full select-none bg-[#c9b998]"
    viewBox="0 0 1000 636"
    preserveAspectRatio="xMidYMid meet"
    aria-labelledby="game-map-title game-map-description"
  >
    <title id="game-map-title">Detective: City of Angels investigation board</title>
    <desc id="game-map-description">
      Official game board with server-authorized location hotspots, Detective tokens, and revealed suspect standees.
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

    <g id="suspect-standees" aria-label="Revealed suspects">
      {#each suspects as suspect (suspect.id)}
        {@const placement = suspectPlacement(suspect)}
        {#if placement}
          {@const actions = suspectActions(suspect)}
          {@const actionable = actions.length > 0}
          <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
          <g
            id={`suspect-map-standee-${suspect.id}`}
            data-testid={`suspect-standee-${suspect.id}`}
            data-location-id={placement.location.id}
            class={`map-suspect-standee ${actionable ? "map-suspect-standee-actionable" : ""} ${selectedSuspectId === suspect.id ? "map-suspect-standee-selected" : ""}`}
            style={`transform: translate(${placement.x}px, ${placement.y}px);`}
            role={actionable ? "button" : "img"}
            tabindex={actionable ? "0" : undefined}
            focusable={actionable ? "true" : "false"}
            aria-pressed={actionable ? selectedSuspectId === suspect.id : undefined}
            aria-label={suspectLabel(suspect, placement.location, actions)}
            data-actionable={actionable}
            data-selected={selectedSuspectId === suspect.id}
            onclick={(event) => selectSuspectStandee(event, suspect, actions)}
            onkeydown={(event) => selectSuspectStandee(event, suspect, actions)}
          >
            <title>{suspectLabel(suspect, placement.location, actions)}</title>
            <ellipse
              cx="0"
              cy="-3"
              rx="21"
              ry="29"
              class="map-suspect-action-ring"
              vector-effect="non-scaling-stroke"
              aria-hidden="true"
            />
            <rect
              x="-14"
              y="-25"
              width="28"
              height="37"
              rx="3"
              class="map-suspect-card"
              vector-effect="non-scaling-stroke"
            />
            <circle cx="0" cy="-13" r="7" class="map-suspect-portrait" />
            <path d="M-9 5C-8-4-4-7 0-7S8-4 9 5Z" class="map-suspect-silhouette" />
            <text
              y="9"
              text-anchor="middle"
              class="map-suspect-initials"
            >{suspectInitials(suspect.name)}</text>
            <path
              d="M-17 12H17L12 20H-12Z"
              class="map-suspect-base"
              vector-effect="non-scaling-stroke"
            />
          </g>
        {/if}
      {/each}
    </g>

    <g id="detective-tokens" filter="url(#token-shadow)">
      {#each detectives as detective}
        {@const tokenLocation = locations.find((location) => location.id === detective.location_id)}
        {#if tokenLocation}
          {@const actions = detective.id === actionableDetectiveId ? availableDetectiveActions : []}
          {@const actionable = actions.length > 0}
          <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
          <g
            id={`detective-map-token-${detective.id}`}
            data-testid={`detective-token-${detective.id}`}
            class={`map-detective-token ${lastTravel?.player_id === detective.id ? "map-detective-token-active" : ""} ${actionable ? "map-detective-token-actionable" : ""} ${selectedDetectiveId === detective.id ? "map-detective-token-selected" : ""}`}
            style={`transform: translate(${tokenLocation.x * 1000 + (detective.seat - 1) * 11}px, ${tokenLocation.y * 636 - 16}px);`}
            role={actionable ? "button" : "img"}
            tabindex={actionable ? "0" : undefined}
            focusable={actionable ? "true" : "false"}
            aria-pressed={actionable ? selectedDetectiveId === detective.id : undefined}
            aria-label={detectiveLabel(detective, tokenLocation, actions)}
            data-actionable={actionable}
            data-selected={selectedDetectiveId === detective.id}
            onclick={(event) => selectDetectiveToken(event, detective, actions)}
            onkeydown={(event) => selectDetectiveToken(event, detective, actions)}
          >
            <circle
              r="27"
              class="map-detective-action-ring"
              vector-effect="non-scaling-stroke"
              aria-hidden="true"
            />
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

  <CaseCardRail slots={caseCardSlots} players={detectives} />

  <nav
    id="legal-map-destinations"
    class="map-destination-fallback"
    aria-label="Legal map destinations"
  >
    {#if legalLocations.length > 0}
      <p class="map-destination-fallback-title">Keyboard destinations</p>
      <div class="map-destination-fallback-list">
        {#each legalLocations as location}
          <button
            id={`map-destination-${location.id}`}
            type="button"
            data-location-id={location.id}
            aria-controls="game-map"
            class="map-destination-fallback-button"
            aria-pressed={selectedLocationId === location.id}
            onclick={(event) => select(event, location)}
          >
            Choose {location.name}
          </button>
        {/each}
      </div>
    {:else}
      <p class="map-destination-fallback-empty">
        No map destination is available for this player.
      </p>
    {/if}
  </nav>
</div>
