<script>
  import CaseCardRail from "./CaseCardRail.svelte"
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
    onSelect = () => {},
    onSelectDetective = () => {},
    onSelectSuspect = () => {},
    onSelectSpecialActor = () => {},
    onSelectCaseCard = () => {},
  } = $props()

  let legalIds = $derived(new Set(disabled ? [] : legalLocationIds))
  let searchableIds = $derived(
    new Set(disabled || suspectInteractionsDisabled ? [] : searchableSuspectIds),
  )
  let interrogatableIds = $derived(
    new Set(disabled || suspectInteractionsDisabled ? [] : interrogatableSuspectIds),
  )
  let interactableActorIds = $derived(
    new Set(
      disabled || specialActorInteractionsDisabled ? [] : interactableSpecialActorIds,
    ),
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

  function detectivePortrait(seat) {
    return `/images/ui/noir/portraits/detective-${Math.min(Math.max(seat, 1), 4)}.webp`
  }

  function detectiveActionLabel(action) {
    return (
      {
        search_location: t("search location"),
        analyze: t("analyze evidence"),
        kickback: t("collect kickback"),
        bribe_officer: t("bribe officer"),
      }[action] ?? action.replaceAll("_", " ")
    )
  }

  function detectiveLabel(detective, location, actions) {
    const identity = t("{name} at {location}", { name: detective.display_name, location: location.name })
    return actions.length > 0
      ? t("{identity}. Available actions: {actions}.", { identity, actions: actions.map(detectiveActionLabel).join(", ") })
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

  function suspectPortraitVariant(id) {
    return (
      Array.from(String(id)).reduce(
        (sum, character, index) => sum + character.charCodeAt(0) * (index + 1),
        0,
      ) % 4
    )
  }

  function suspectActions(suspect) {
    return [
      searchableIds.has(suspect.id) ? t("search") : null,
      interrogatableIds.has(suspect.id) ? t("question") : null,
    ].filter(Boolean)
  }

  function suspectLabel(suspect, location, actions) {
    const identity = t("{name}, {occupation}, at {location}", { name: suspect.name, occupation: suspect.occupation, location: location.name })
    return actions.length > 0
      ? t("{identity}. Available actions: {actions}.", { identity, actions: actions.join(t(" and ")) })
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

  function specialActorPlacement(actor) {
    const location = locations.find((candidate) => candidate.id === actor.location_id)
    if (!location) return null

    const colocated = specialActors.filter(
      (candidate) => candidate.location_id === actor.location_id,
    )
    const index = colocated.findIndex((candidate) => candidate.id === actor.id)
    const offset = (index - (colocated.length - 1) / 2) * 24

    return {
      location,
      x: location.x * 1000 + 34 + offset,
      y: location.y * 636 - 42,
    }
  }

  function specialActorLabel(actor, location, actionable) {
    const status = actor.active ? t("active") : t("neutralized")
    const action = actionable ? t(" Select to review special interactions.") : ""
    return t("{name}, {role}, at {location}. {status}.{action}", { name: actor.name, role: actor.role, location: location.name, status, action })
  }

  function locationMarkerLabel(location) {
    return /^\d+$/.test(String(location.id)) ? location.id : "→"
  }

  function selectSpecialActor(event, actor, actionable) {
    if (!actionable) return
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return
    if (event.type === "keydown") event.preventDefault()
    onSelectSpecialActor(actor)
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
    <title id="game-map-title">{t("Detective: City of Angels investigation board")}</title>
    <desc id="game-map-description">
      {t("Official game board with server-authorized location hotspots, Detective tokens, and revealed suspect standees.")}
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
      <clipPath id="detective-token-portrait-clip" clipPathUnits="userSpaceOnUse">
        <circle r="16" />
      </clipPath>
      <radialGradient id="detective-token-rim" cx="32%" cy="25%" r="76%">
        <stop offset="0" stop-color="#f7dda0" />
        <stop offset="0.28" stop-color="#c99a45" />
        <stop offset="0.72" stop-color="#765025" />
        <stop offset="1" stop-color="#2f1c0d" />
      </radialGradient>
    </defs>

    <image
      data-testid="official-board-image"
      href="/images/maps/dcoa/game-board-final-v1.webp"
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
          aria-label={legal ? t("Select {location} on the map", { location: location.name }) : undefined}
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
            >{locationMarkerLabel(location)}</text>
          {/if}
        </g>
      {/each}
    </g>

    <g id="suspect-standees" aria-label={t("Revealed suspects")}>
      {#each suspects as suspect (suspect.id)}
        {@const placement = suspectPlacement(suspect)}
        {#if placement}
          {@const actions = suspectActions(suspect)}
          {@const actionable = actions.length > 0}
          {@const portraitVariant = suspectPortraitVariant(suspect.id)}
          <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
          <g
            id={`suspect-map-standee-${suspect.id}`}
            data-testid={`suspect-standee-${suspect.id}`}
            data-location-id={placement.location.id}
            data-portrait-variant={portraitVariant}
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
              cy="-4"
              rx="25"
              ry="34"
              class="map-suspect-action-ring"
              vector-effect="non-scaling-stroke"
              aria-hidden="true"
            />
            <rect
              x="-17"
              y="-29"
              width="34"
              height="44"
              rx="2"
              class="map-suspect-card"
              vector-effect="non-scaling-stroke"
            />
            <path d="M12-29H17V-24Z" class="map-suspect-card-fold" />
            <rect x="-13" y="-25" width="26" height="25" rx="1.5" class="map-suspect-photo-well" />
            <g class="map-suspect-portrait-art" aria-hidden="true">
              <path d="M-11 0C-10-8-5-10 0-10S10-8 11 0Z" class="map-suspect-coat" />
              <ellipse cx="0" cy="-13" rx="6.2" ry="7.4" class="map-suspect-face" />
              {#if portraitVariant === 0}
                <path d="M-8-17H8L5-22H-4Z" class="map-suspect-feature" />
                <path d="M-11-16H11" class="map-suspect-detail" />
              {:else if portraitVariant === 1}
                <path d="M-7-19Q0-24 7-19L8-7 4-10 5-18Q0-21-5-18L-4-9-8-7Z" class="map-suspect-feature" />
              {:else if portraitVariant === 2}
                <path d="M-7-18Q0-23 7-18L5-20H-5Z" class="map-suspect-feature" />
                <circle cx="-3" cy="-13" r="2.4" class="map-suspect-glasses" />
                <circle cx="3" cy="-13" r="2.4" class="map-suspect-glasses" />
                <path d="M-0.6-13H0.6" class="map-suspect-detail" />
              {:else}
                <path d="M-7-18Q0-23 8-18L6-15H-7Z" class="map-suspect-feature" />
                <path d="M-8-17H9" class="map-suspect-detail" />
              {/if}
            </g>
            <rect x="-14" y="2" width="28" height="10" rx="1" class="map-suspect-nameplate" />
            <text
              y="9.2"
              text-anchor="middle"
              class="map-suspect-initials"
            >{suspectInitials(suspect.name)}</text>
            <path
              d="M-21 15H21L15 24H-15Z"
              class="map-suspect-base"
              vector-effect="non-scaling-stroke"
            />
            <circle cx="-12" cy="19" r="1.2" class="map-suspect-rivet" />
            <circle cx="12" cy="19" r="1.2" class="map-suspect-rivet" />
          </g>
        {/if}
      {/each}
    </g>

    <g id="special-actor-tokens" aria-label={t("Case-specific people and contacts")}>
      {#each specialActors as actor (actor.id)}
        {@const placement = specialActorPlacement(actor)}
        {#if placement}
          {@const actionable = actor.active && interactableActorIds.has(actor.id)}
          <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
          <g
            id={`special-actor-token-${actor.id}`}
            data-testid={`special-actor-${actor.id}`}
            data-location-id={placement.location.id}
            data-kind={actor.kind}
            data-active={actor.active}
            data-actionable={actionable}
            data-selected={selectedSpecialActorId === actor.id}
            class={`map-special-actor ${actor.active ? "" : "map-special-actor-disabled"} ${actionable ? "map-special-actor-actionable" : ""} ${selectedSpecialActorId === actor.id ? "map-special-actor-selected" : ""}`}
            style={`transform: translate(${placement.x}px, ${placement.y}px);`}
            role={actionable ? "button" : "img"}
            tabindex={actionable ? "0" : undefined}
            focusable={actionable ? "true" : "false"}
            aria-pressed={actionable ? selectedSpecialActorId === actor.id : undefined}
            aria-label={specialActorLabel(actor, placement.location, actionable)}
            onclick={(event) => selectSpecialActor(event, actor, actionable)}
            onkeydown={(event) => selectSpecialActor(event, actor, actionable)}
          >
            <title>{specialActorLabel(actor, placement.location, actionable)}</title>
            <circle r="25" class="map-special-actor-ring" vector-effect="non-scaling-stroke" />
            <path d="M-15-17H15L19 12 0 21-19 12Z" class="map-special-actor-badge" />
            <path d="M-8-8 0-14 8-8V2L0 8-8 2Z" class="map-special-actor-eye" />
            <path d="M-11 13H11" class="map-special-actor-mark" vector-effect="non-scaling-stroke" />
            {#if !actor.active}
              <path d="M-17-17 17 17" class="map-special-actor-strike" vector-effect="non-scaling-stroke" />
            {/if}
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
            data-seat={detective.seat}
            data-actionable={actionable}
            data-selected={selectedDetectiveId === detective.id}
            onclick={(event) => selectDetectiveToken(event, detective, actions)}
            onkeydown={(event) => selectDetectiveToken(event, detective, actions)}
          >
            <circle
              r="29"
              class="map-detective-action-ring"
              vector-effect="non-scaling-stroke"
              aria-hidden="true"
            />
            <circle
              r="23"
              class="map-detective-chip"
              fill={tokenColor(detective.seat)}
              stroke="url(#detective-token-rim)"
              stroke-width="6"
              vector-effect="non-scaling-stroke"
            />
            <circle r="17.5" class="map-detective-photo-well" />
            <image
              data-testid={`detective-token-portrait-${detective.id}`}
              href={detectivePortrait(detective.seat)}
              x="-16"
              y="-16"
              width="32"
              height="32"
              preserveAspectRatio="xMidYMid slice"
              clip-path="url(#detective-token-portrait-clip)"
              class="map-detective-photo"
            />
            <circle r="16.5" class="map-detective-photo-bezel" vector-effect="non-scaling-stroke" />
            <path d="M-14-14A20 20 0 0 1 13-15" class="map-detective-chip-glint" />
            <circle cx="15" cy="15" r="8" class="map-detective-seat-badge" />
            <text
              x="15"
              y="18"
              text-anchor="middle"
              fill="#fff0d2"
              stroke="#2d1d10"
              stroke-width="1.5"
              paint-order="stroke"
              font-family="IBM Plex Mono, monospace"
              font-size="8"
              font-weight="700"
            >{detective.seat}</text>
          </g>
        {/if}
      {/each}
    </g>
  </svg>

  <CaseCardRail
    slots={caseCardSlots}
    players={detectives}
    {inspectableCaseCardCodes}
    {selectedCaseCardCode}
    {disabled}
    {onSelectCaseCard}
  />

  <nav
    id="legal-map-destinations"
    class="map-destination-fallback"
    aria-label={t("Legal map destinations")}
  >
    {#if legalLocations.length > 0}
      <p class="map-destination-fallback-title">{t("Keyboard destinations")}</p>
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
            {t("Choose {location}", { location: location.name })}
          </button>
        {/each}
      </div>
    {:else}
      <p class="map-destination-fallback-empty">
        {t("No map destination is available for this player.")}
      </p>
    {/if}
  </nav>
</div>
