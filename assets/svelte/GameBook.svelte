<script>
  import { onMount } from "svelte"

  let { game_id, user_id, initial_public, initial_private } = $props()

  const initialPublic = () => initial_public
  const initialPrivate = () => initial_private

  let publicState = $state(initialPublic())
  let privateState = $state(initialPrivate())
  let connectionState = $state("connecting")
  let selectedLocationId = $state(null)
  let selectedSuspectId = $state(null)
  let selectedTopicId = $state(null)
  let selectedResponseId = $state(null)
  let spendLeverage = $state(false)
  let commandPending = $state(false)
  let retryCommand = $state(null)
  let commandError = $state(null)
  let lastEvent = $state("Casebook synchronized.")
  let gameChannel = null
  let userChannel = null
  const seenPublicEventIds = new Set()
  const seenPrivateEventIds = new Set()

  let detectives = $derived(publicState.players.filter((player) => player.role === "detective"))
  let chisel = $derived(publicState.players.find((player) => player.role === "chisel"))
  let ownPlayer = $derived(publicState.players.find((player) => player.id === privateState.player_id))
  let activeDetective = $derived(
    publicState.players.find((player) => player.id === publicState.current_detective_id),
  )
  let selectedLocation = $derived(
    publicState.locations.find((location) => location.id === selectedLocationId),
  )
  let moveLocationIds = $derived(new Set(privateState.valid_move_location_ids ?? []))
  let placementLocationIds = $derived(new Set(privateState.placement_location_ids ?? []))
  let availableActions = $derived(new Set(privateState.available_actions ?? []))
  let interrogationOptions = $derived(privateState.interrogation_options ?? [])
  let interrogatableSuspectIds = $derived(
    new Set(interrogationOptions.map((option) => option.suspect_id)),
  )
  let selectedInterrogation = $derived(
    interrogationOptions.find((option) => option.suspect_id === selectedSuspectId),
  )
  let selectedTopic = $derived(
    selectedInterrogation?.topics.find((topic) => topic.id === selectedTopicId),
  )
  let pendingPublic = $derived(publicState.pending_interrogation)
  let pendingPrivate = $derived(privateState.pending_interrogation)
  let latestStatement = $derived(privateState.statements?.[0])
  let selectedSuspectLeverage = $derived(
    privateState.leverage_on_suspects?.[selectedSuspectId] ?? 0,
  )

  let mapConnections = $derived.by(() => {
    const connections = []

    for (let leftIndex = 0; leftIndex < publicState.locations.length; leftIndex += 1) {
      for (let rightIndex = leftIndex + 1; rightIndex < publicState.locations.length; rightIndex += 1) {
        const left = publicState.locations[leftIndex]
        const right = publicState.locations[rightIndex]
        const sharesDistrict = left.district_ids.some((district) => right.district_ids.includes(district))

        if (sharesDistrict) connections.push({ left, right })
      }
    }

    return connections
  })

  function applyPublic(nextState) {
    if (nextState.version < publicState.version) return
    publicState = nextState
  }

  function applyPrivate(nextState, version) {
    if (version < publicState.version) return
    privateState = nextState
  }

  function acceptEvent({ event_id, version }, seenEventIds) {
    if (version < publicState.version) return false
    if (!event_id) return true
    if (seenEventIds.has(event_id)) return false

    seenEventIds.add(event_id)
    return true
  }

  function recordPublicEvent(message, description) {
    if (acceptEvent(message, seenPublicEventIds)) lastEvent = description
  }

  function locationAction(location) {
    selectedLocationId = location.id

    if (commandPending || connectionState !== "online") return

    if (placementLocationIds.has(location.id) && availableActions.has("place")) {
      sendCommand("place", { location_id: location.id })
    } else if (moveLocationIds.has(location.id) && availableActions.has("move")) {
      sendCommand("move", { location_id: location.id })
    }
  }

  function locationKeydown(event, location) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      locationAction(location)
    }
  }

  function sendCommand(type, payload, existingCommand = null) {
    if (!gameChannel || commandPending) return

    const command =
      existingCommand ??
      {
        command_id: crypto.randomUUID(),
        type,
        expected_version: publicState.version,
        payload,
      }

    commandPending = true
    commandError = null
    retryCommand = null

    gameChannel
      .push("command", command)
      .receive("ok", () => {
        commandPending = false
        retryCommand = null
      })
      .receive("error", ({ code }) => {
        commandPending = false
        retryCommand = null
        commandError = commandErrorMessage(code)
      })
      .receive("timeout", () => {
        commandPending = false
        retryCommand = command
        commandError = "Command unconfirmed. Retry uses the same command ID."
      })
  }

  function retryLastCommand() {
    if (retryCommand) sendCommand(retryCommand.type, retryCommand.payload, retryCommand)
  }

  function commandErrorMessage(code) {
    const messages = {
      stale_version: "The case advanced before this action. Reload the current state.",
      not_your_turn: "Only the active Detective can act.",
      wrong_role: "This action belongs to a Detective.",
      placement_required: "Place your token at a Police Station first.",
      destination_outside_district: "That location is outside the current district.",
      no_actions_remaining: "No actions remain this turn.",
      mob_joint_required: "Kickback is available only at a Mob Joint.",
      kickback_already_used: "Kickback was already used today.",
      invalid_suspect: "That suspect is not available in this case.",
      suspect_not_at_location: "Move to the suspect's location before questioning them.",
      topic_not_known: "That case topic has not been discovered.",
      invalid_response: "That response is not available for this question.",
      response_forced_truthful: "Spent leverage requires the most useful response.",
      suspect_leverage_required: "No leverage is available over that suspect.",
      no_leverage_remaining: "No leverage marker remains to stake on a challenge.",
      not_interrogating_detective: "Only the Detective who asked may decide.",
    }

    return messages[code] ?? "The server rejected this action."
  }

  function legalLocation(locationId) {
    return moveLocationIds.has(locationId) || placementLocationIds.has(locationId)
  }

  function locationLabel(location) {
    if (placementLocationIds.has(location.id)) return `${location.name}. Place here for free.`
    if (moveLocationIds.has(location.id)) return `${location.name}. Move here for one action.`
    return location.name
  }

  function locationType(type) {
    if (type === "police_station") return "Police Station"
    if (type === "mob_joint") return "Mob Joint"
    return "Location"
  }

  function locationName(locationId) {
    return publicState.locations.find((location) => location.id === locationId)?.name ?? locationId
  }

  function selectSuspect(suspectId) {
    if (!interrogatableSuspectIds.has(suspectId) || commandPending) return

    selectedSuspectId = suspectId
    selectedTopicId =
      interrogationOptions.find((option) => option.suspect_id === suspectId)?.topics[0]?.id ?? null
    spendLeverage = false
  }

  function submitInterrogation() {
    if (!selectedSuspectId || !selectedTopicId) return

    sendCommand("interrogate", {
      suspect_id: selectedSuspectId,
      topic_id: selectedTopicId,
      spend_leverage: spendLeverage,
    })
  }

  function submitResponse() {
    if (!selectedResponseId || !pendingPrivate?.id) return
    sendCommand("select_response", { response_id: selectedResponseId })
  }

  onMount(() => {
    const socket = window.getGameSocket?.()
    if (!socket) {
      connectionState = "offline"
      return
    }

    gameChannel = socket.channel(`game:${game_id}`, {})
    userChannel = socket.channel(`user:${user_id}`, { game_id })

    gameChannel.on("game_state", ({ state }) => applyPublic(state))
    gameChannel.on("detective_placed", (message) =>
      recordPublicEvent(message, "A Detective entered the city."),
    )
    gameChannel.on("player_moved", (message) =>
      recordPublicEvent(message, "A Detective moved to a new location."),
    )
    gameChannel.on("evidence_analyzed", (message) =>
      recordPublicEvent(message, "Evidence was analyzed."),
    )
    gameChannel.on("kickback_collected", (message) =>
      recordPublicEvent(message, "A contact paid out a kickback."),
    )
    gameChannel.on(
      "interrogation_started",
      (message) => recordPublicEvent(message, "A suspect was called in for questioning."),
    )
    gameChannel.on(
      "response_published",
      (message) =>
        recordPublicEvent(message, "The suspect's statement was delivered under seal."),
    )
    gameChannel.on(
      "response_accepted",
      (message) => recordPublicEvent(message, "The statement was accepted into the casefile."),
    )
    gameChannel.on(
      "challenge_succeeded",
      (message) =>
        recordPublicEvent(message, "Challenge sustained. The suspect changed their statement."),
    )
    gameChannel.on(
      "challenge_failed",
      (message) =>
        recordPublicEvent(message, "Challenge failed. The Chisel gained leverage."),
    )
    gameChannel.on("turn_started", (message) =>
      recordPublicEvent(message, "A new Detective turn began."),
    )
    gameChannel.on("day_advanced", (message) =>
      recordPublicEvent(message, "The investigation advanced one day."),
    )
    gameChannel.on("accusation_opened", (message) =>
      recordPublicEvent(message, "Time expired. The accusation phase is open."),
    )

    userChannel.on("private_state", ({ game_id: eventGameId, state, version }) => {
      if (eventGameId === game_id) applyPrivate(state, version)
    })

    userChannel.on("private_event", (message) => {
      const { game_id: eventGameId, payload } = message
      if (eventGameId !== game_id) return
      if (!acceptEvent(message, seenPrivateEventIds)) return

      if (payload.type === "challenge_resolved") {
        lastEvent = payload.succeeded
          ? "Challenge sustained. The corrected statement is now in your notes."
          : "Challenge failed. The original statement was truthful."
      }
    })

    gameChannel
      .join()
      .receive("ok", ({ state }) => {
        applyPublic(state)
        connectionState = "online"
      })
      .receive("error", () => (connectionState = "unauthorized"))
      .receive("timeout", () => (connectionState = "offline"))

    userChannel
      .join()
      .receive("ok", ({ state, version }) => applyPrivate(state, version))
      .receive("error", () => (connectionState = "unauthorized"))

    return () => {
      gameChannel?.leave()
      userChannel?.leave()
      gameChannel = null
      userChannel = null
    }
  })
</script>

<div id="game-book-shell" class="min-h-[calc(100dvh-3.5rem)] overflow-hidden bg-[#17130f] text-[#241d17]">
  <div class="mx-auto flex min-h-[calc(100dvh-3.5rem)] max-w-[1800px] flex-col px-2 py-3 sm:px-4 lg:px-6 lg:py-5">
    <header class="mb-3 flex flex-wrap items-center justify-between gap-3 px-1 text-[#d8cdb8]">
      <div class="flex items-center gap-3">
        <span class="font-mono text-[11px] uppercase tracking-[0.18em] text-[#d96b58]">Case in progress</span>
        <span class="h-3 w-px bg-white/20" aria-hidden="true"></span>
        <span class="font-mono text-[11px] uppercase tracking-[0.14em]">Day {publicState.day} · {publicState.days_remaining} left</span>
      </div>
      <div class="flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.12em]">
        <span class={connectionState === "online" ? "text-emerald-300" : "text-stone-400"}>{connectionState}</span>
        <span class="text-stone-500">v{publicState.version}</span>
      </div>
    </header>

    <main
      id="open-casebook"
      class="relative grid min-h-0 flex-1 overflow-hidden border border-[#6f5b45] bg-[#d8c9aa] shadow-[0_24px_70px_rgba(0,0,0,0.55)] lg:grid-cols-2"
    >
      <div class="pointer-events-none absolute inset-y-0 left-1/2 z-30 hidden w-9 -translate-x-1/2 bg-[#5a4430] opacity-35 lg:block" aria-hidden="true"></div>
      <div class="pointer-events-none absolute inset-y-0 left-1/2 z-30 hidden w-px bg-[#2f2118]/70 lg:block" aria-hidden="true"></div>

      <svg class="pointer-events-none absolute inset-0 z-20 size-full opacity-[0.07] mix-blend-multiply" aria-hidden="true">
        <filter id="paper-fibers">
          <feTurbulence type="fractalNoise" baseFrequency="0.72" numOctaves="3" seed="17" />
        </filter>
        <rect width="100%" height="100%" filter="url(#paper-fibers)" />
      </svg>

      <section id="casebook-map-page" class="relative z-10 flex min-h-[38rem] flex-col border-b border-[#8d765d] bg-[#d9ccb0] lg:min-h-0 lg:border-b-0 lg:border-r">
        <div class="flex items-start justify-between gap-4 border-b border-[#9f896d] px-4 py-3 sm:px-5">
          <div>
            <p class="font-mono text-[10px] uppercase tracking-[0.18em] text-[#8c3f33]">Plate 01 · field map</p>
            <h1 class="mt-1 font-serif text-2xl font-semibold tracking-[-0.025em] text-[#2e241c]">Greater Los Angeles</h1>
          </div>
          <div class="text-right font-mono text-[10px] uppercase tracking-[0.12em] text-[#6f5d49]">
            <p>{publicState.phase.replaceAll("_", " ")}</p>
            <p class="mt-1">Active: {activeDetective?.display_name ?? "—"}</p>
          </div>
        </div>

        <div class="relative overflow-hidden bg-[#b7a78b] p-2 sm:p-3">
          <svg
            id="game-map"
            class="aspect-[2048/1331] w-full select-none border border-[#6e5c48] bg-[#c9b998]"
            viewBox="0 0 2048 1331"
            preserveAspectRatio="xMidYMid meet"
            role="img"
            aria-labelledby="game-map-title game-map-description"
          >
            <title id="game-map-title">Investigation map with clickable locations</title>
            <desc id="game-map-description">A 1932 Library of Congress map with original game locations, travel links, and Detective tokens.</desc>
            <defs>
              <filter id="map-ink">
                <feColorMatrix type="saturate" values="0.42" />
                <feComponentTransfer>
                  <feFuncR type="linear" slope="0.88" intercept="0.06" />
                  <feFuncG type="linear" slope="0.82" intercept="0.08" />
                  <feFuncB type="linear" slope="0.7" intercept="0.1" />
                </feComponentTransfer>
              </filter>
              <filter id="token-shadow" x="-80%" y="-80%" width="260%" height="260%">
                <feDropShadow dx="0" dy="9" stdDeviation="7" flood-color="#211810" flood-opacity="0.6" />
              </filter>
            </defs>

            <image
              href="/images/maps/leuschner-1932/map-2048.jpg"
              width="2048"
              height="1331"
              filter="url(#map-ink)"
              opacity="0.9"
            />
            <rect width="2048" height="1331" fill="#8c6e3c" opacity="0.08" />

            <g id="district-links" opacity="0.52">
              {#each mapConnections as connection}
                <line
                  x1={connection.left.x * 2048}
                  y1={connection.left.y * 1331}
                  x2={connection.right.x * 2048}
                  y2={connection.right.y * 1331}
                  stroke="#6b3027"
                  stroke-width="4"
                  stroke-dasharray="12 16"
                  vector-effect="non-scaling-stroke"
                />
              {/each}
            </g>

            <g id="map-locations">
              {#each publicState.locations as location}
                <g
                  id={`map-location-${location.id}`}
                  transform={`translate(${location.x * 2048} ${location.y * 1331})`}
                  class={legalLocation(location.id) ? "cursor-pointer" : "cursor-default"}
                  role="button"
                  tabindex="0"
                  aria-label={locationLabel(location)}
                  aria-disabled={!legalLocation(location.id)}
                  onclick={() => locationAction(location)}
                  onkeydown={(event) => locationKeydown(event, location)}
                >
                  {#if legalLocation(location.id)}
                    <circle r="42" fill="none" stroke="#c94f3e" stroke-width="7" opacity="0.88">
                      <animate attributeName="opacity" values="0.9;0.38;0.9" dur="2.2s" repeatCount="indefinite" />
                    </circle>
                  {/if}
                  <circle
                    r={selectedLocationId === location.id ? 25 : 20}
                    fill={location.type === "police_station" ? "#243c48" : location.type === "mob_joint" ? "#6f2d2b" : "#e4d5b4"}
                    stroke={selectedLocationId === location.id ? "#f6ead0" : "#3c2b20"}
                    stroke-width="6"
                    vector-effect="non-scaling-stroke"
                  />
                  <path d="M-7-2h14M0-9v14" stroke="#f4e8ce" stroke-width="3" opacity={location.type === "police_station" ? 1 : 0} />
                  <text
                    y="48"
                    text-anchor="middle"
                    fill="#241b14"
                    stroke="#eadfca"
                    stroke-width="8"
                    paint-order="stroke"
                    font-family="IBM Plex Sans, sans-serif"
                    font-size="23"
                    font-weight="600"
                  >{location.name}</text>
                </g>
              {/each}
            </g>

            <g id="detective-tokens" filter="url(#token-shadow)">
              {#each detectives as detective}
                {@const tokenLocation = publicState.locations.find((location) => location.id === detective.location_id)}
                {#if tokenLocation}
                  <g transform={`translate(${tokenLocation.x * 2048 + (detective.seat - 1) * 22} ${tokenLocation.y * 1331 - 28})`}>
                    <path d="M0-32 27-14 20 25 0 39-20 25-27-14Z" fill={["#28485c", "#724438", "#3f5d44", "#6b5535"][detective.seat - 1]} stroke="#f2e4c8" stroke-width="5" />
                    <text y="8" text-anchor="middle" fill="#f8ecd2" font-family="IBM Plex Mono, monospace" font-size="22" font-weight="600">D{detective.seat}</text>
                  </g>
                {/if}
              {/each}
            </g>
          </svg>

          <p class="absolute bottom-4 left-5 max-w-[72%] bg-[#e4d7bd]/92 px-2 py-1 font-mono text-[8px] leading-3 text-[#594936] sm:text-[9px]">
            Map: K. M. Leuschner and Metropolitan Surveys, 1932. Library of Congress, Geography and Map Division.
          </p>
        </div>

        <section class="flex flex-1 flex-col border-t border-[#8d765d] px-4 py-4 sm:px-5" aria-labelledby="movement-ledger-heading">
          <div class="grid gap-4 sm:grid-cols-[1.25fr_0.75fr]">
            <div>
              <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Travel rule · field note</p>
              <h2 id="movement-ledger-heading" class="mt-1 font-serif text-lg font-semibold">District movement ledger</h2>
              <p class="mt-2 max-w-xl text-xs leading-5 text-[#695642]">
                One Move action reaches any location in the current district. A location filed under two districts is a border stop; enter it first, then spend another Move to cross.
              </p>
            </div>
            <dl class="grid grid-cols-2 gap-x-3 gap-y-2 self-start font-mono text-[9px] uppercase tracking-[0.08em] text-[#6e5943]">
              <div class="border-t border-[#9e876a] pt-2"><dt>Blue cross</dt><dd class="mt-1 text-[#2f4551]">Police Station</dd></div>
              <div class="border-t border-[#9e876a] pt-2"><dt>Red marker</dt><dd class="mt-1 text-[#7a302c]">Mob Joint</dd></div>
              <div class="border-t border-[#9e876a] pt-2"><dt>Red ring</dt><dd class="mt-1 text-[#9e3f34]">Legal command</dd></div>
              <div class="border-t border-[#9e876a] pt-2"><dt>Dashed ink</dt><dd class="mt-1">Shared district</dd></div>
            </dl>
          </div>

          <div class="mt-4 border-t border-[#9e876a] pt-3">
            <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Known persons · public file</p>
            <div class="mt-2 grid gap-2 sm:grid-cols-3">
              {#each publicState.suspects as suspect, index}
                <button
                  id={`interrogate-suspect-${suspect.id}`}
                  type="button"
                  disabled={!interrogatableSuspectIds.has(suspect.id) || commandPending}
                  aria-pressed={selectedSuspectId === suspect.id}
                  onclick={() => selectSuspect(suspect.id)}
                  class={`flex min-h-14 items-center gap-2 border p-2 text-left transition ${selectedSuspectId === suspect.id ? "border-[#8f342d] bg-[#f0dfbd] ring-2 ring-[#a54235]" : "border-[#a18a6d] bg-[#e6d9bd]"} ${interrogatableSuspectIds.has(suspect.id) ? "cursor-pointer hover:bg-[#f2e4c8]" : "cursor-default"}`}
                >
                  <svg class="size-10 shrink-0 bg-[#30261f]" viewBox="0 0 48 48" role="img" aria-label={`Original portrait sketch for ${suspect.name}`}>
                    <rect width="48" height="48" fill={["#3d5360", "#6a4337", "#4b5d44"][index % 3]} />
                    <circle cx="24" cy="20" r="9" fill="#d0aa82" />
                    <path d={index % 3 === 0 ? "M13 18c4-12 18-12 22 0Z" : index % 3 === 1 ? "M12 17h24l-5-7H18Z" : "M14 20c2-12 18-13 21 0l-6-7-5 6Z"} fill="#211a16" />
                    <path d="M8 48c2-12 8-18 16-18s14 6 16 18Z" fill="#242321" />
                  </svg>
                  <div class="min-w-0">
                    <h3 class="truncate font-serif text-xs font-semibold">{suspect.name}</h3>
                    <p class="mt-0.5 truncate font-mono text-[8px] uppercase tracking-[0.06em] text-[#705b45]">{suspect.occupation}</p>
                    <p class="mt-1 truncate text-[9px] text-[#7e6951]">{locationName(suspect.location_id)}</p>
                  </div>
                </button>
              {/each}
            </div>
          </div>
        </section>
      </section>

      <section id="casebook-action-page" class="relative z-10 flex min-h-[42rem] flex-col bg-[#e4d8bd] lg:min-h-0">
        <div id="detective-bookmarks" class="grid grid-cols-2 border-b border-[#9f896d] sm:grid-cols-4">
          {#each [1, 2, 3, 4] as seat}
            {@const detective = detectives.find((player) => player.seat === seat)}
            <article
              id={`detective-hud-${seat}`}
              class={`relative min-h-24 border-[#a38b6e] p-2.5 sm:border-r ${detective?.id === publicState.current_detective_id ? "bg-[#f0e3c8]" : "bg-[#cbbb9d]"}`}
              aria-current={detective?.id === publicState.current_detective_id ? "true" : undefined}
            >
              {#if detective}
                <div class="flex items-center gap-2">
                  <svg class="size-11 shrink-0 border border-[#6f5942] bg-[#2a211a]" viewBox="0 0 64 64" role="img" aria-label={`Original portrait token for ${detective.display_name}`}>
                    <rect width="64" height="64" fill={["#29475a", "#704239", "#3e5c43", "#685234"][seat - 1]} />
                    <circle cx="32" cy="28" r="13" fill="#d8b38c" />
                    {#if seat === 1}
                      <path d="M15 21h34l-8-9H24Z" fill="#17191a" />
                    {:else if seat === 2}
                      <path d="M18 27c3-15 25-18 30-2-8-4-21-3-30 2Z" fill="#2b1814" />
                    {:else if seat === 3}
                      <path d="M17 23c8-15 26-15 32 2l-8-3-8-10-6 10Z" fill="#1b201a" />
                    {:else}
                      <path d="M18 19h28l5 8H13Z" fill="#2c251c" />
                    {/if}
                    <path d="M12 64c2-17 12-24 20-24s19 7 21 24Z" fill="#1e2425" />
                    <circle cx="27" cy="28" r="1.5" fill="#211812" />
                    <circle cx="38" cy="28" r="1.5" fill="#211812" />
                  </svg>
                  <div class="min-w-0">
                    <p class="truncate text-xs font-semibold text-[#30251c]">{detective.display_name}</p>
                    <p class="mt-1 font-mono text-[10px] text-[#705b45]">AP {detective.actions_remaining}/4</p>
                    <p class="truncate font-mono text-[9px] uppercase tracking-[0.08em] text-[#826a50]">{detective.location_id ?? "Not placed"}</p>
                  </div>
                </div>
                {#if detective.id === publicState.current_detective_id}
                  <span class="absolute inset-x-0 bottom-0 h-1 bg-[#a54235]" aria-hidden="true"></span>
                {/if}
              {:else}
                <div class="flex h-full items-center justify-center font-mono text-[10px] uppercase tracking-[0.12em] text-[#8a755b]">Empty bookmark {seat}</div>
              {/if}
            </article>
          {/each}
        </div>

        <div class="grid min-h-0 flex-1 gap-0 xl:grid-cols-[minmax(0,1fr)_15rem]">
          <div class="min-h-0 p-4 sm:p-5">
            <div class="flex flex-wrap items-start justify-between gap-4 border-b border-[#a38b6e] pb-4">
              <div>
                <p class="font-mono text-[10px] uppercase tracking-[0.18em] text-[#8c3f33]">Action ledger</p>
                <h2 class="mt-1 font-serif text-2xl font-semibold text-[#2e241c]">{activeDetective?.display_name ?? "Accusation"}</h2>
                <p class="mt-1 text-sm text-[#695642]">
                  {privateState.role === "detective" && ownPlayer?.id === publicState.current_detective_id
                    ? "Your turn. Legal map locations are marked in red ink."
                    : "Observing the active Detective's turn."}
                </p>
              </div>
              {#if privateState.role === "detective"}
                <dl class="grid grid-cols-3 gap-4 text-right">
                  <div>
                    <dt class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#80694f]">Actions</dt>
                    <dd class="mt-1 font-mono text-lg font-semibold">{ownPlayer?.actions_remaining ?? 0}</dd>
                  </div>
                  <div>
                    <dt class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#80694f]">Scratch</dt>
                    <dd class="mt-1 font-mono text-lg font-semibold">${privateState.scratch}</dd>
                  </div>
                  <div>
                    <dt class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#80694f]">Leverage</dt>
                    <dd class="mt-1 font-mono text-lg font-semibold">{privateState.leverage_supply}</dd>
                  </div>
                </dl>
              {/if}
            </div>

            <div class="mt-5 grid gap-5 sm:grid-cols-[minmax(12rem,1fr)_minmax(10rem,0.72fr)]">
              <section aria-labelledby="selected-location-heading">
                <p class="font-mono text-[10px] uppercase tracking-[0.14em] text-[#80694f]">Selected location</p>
                {#if selectedLocation}
                  <h3 id="selected-location-heading" class="mt-2 font-serif text-xl font-semibold">{selectedLocation.name}</h3>
                  <p class="mt-2 text-sm leading-6 text-[#695642]">
                    {locationType(selectedLocation.type)} · {selectedLocation.district_ids.join(" / ")}
                  </p>
                  {#if placementLocationIds.has(selectedLocation.id)}
                    <p class="mt-3 border-l-2 border-[#a54235] pl-3 text-sm">First-turn placement costs no action.</p>
                  {:else if moveLocationIds.has(selectedLocation.id)}
                    <p class="mt-3 border-l-2 border-[#a54235] pl-3 text-sm">Legal Move · costs 1 action.</p>
                  {:else}
                    <p class="mt-3 text-sm text-[#806d56]">Inspect only; no legal movement command is available.</p>
                  {/if}
                {:else}
                  <h3 id="selected-location-heading" class="mt-2 font-serif text-xl font-semibold">Open the map</h3>
                  <p class="mt-2 max-w-md text-sm leading-6 text-[#695642]">Choose a marked location. The browser sends intent; the server validates district, role, turn, and action cost.</p>
                {/if}
              </section>

              <section id="game-actions" aria-labelledby="game-actions-heading">
                <h3 id="game-actions-heading" class="font-mono text-[10px] uppercase tracking-[0.14em] text-[#80694f]">Available actions</h3>
                <div class="mt-2 grid gap-2">
                  <button
                    id="action-analyze"
                    type="button"
                    disabled={!availableActions.has("analyze") || commandPending}
                    onclick={() => sendCommand("analyze", {})}
                    class="flex min-h-10 cursor-pointer items-center justify-between gap-2 border border-[#796349] bg-[#efe2c5] px-3 text-left text-sm font-semibold transition hover:bg-[#f8ecd2] disabled:cursor-not-allowed disabled:opacity-35"
                  >Analyze <span class="shrink-0 font-mono text-[9px]">1 AP → $1</span></button>
                  <button
                    id="action-kickback"
                    type="button"
                    disabled={!availableActions.has("kickback") || commandPending}
                    onclick={() => sendCommand("kickback", {})}
                    class="flex min-h-10 cursor-pointer items-center justify-between gap-2 border border-[#796349] bg-[#efe2c5] px-3 text-left text-sm font-semibold transition hover:bg-[#f8ecd2] disabled:cursor-not-allowed disabled:opacity-35"
                  >Kickback <span class="shrink-0 font-mono text-[9px]">1 AP</span></button>
                  <button
                    id="action-end-turn"
                    type="button"
                    disabled={!availableActions.has("end_turn") || commandPending}
                    onclick={() => sendCommand("end_turn", {})}
                    class="flex min-h-10 cursor-pointer items-center justify-between gap-2 bg-[#9c4035] px-3 text-left text-sm font-semibold text-[#fff0d6] transition hover:bg-[#ad4a3d] disabled:cursor-not-allowed disabled:bg-[#8d7b65]"
                  >End turn <span class="shrink-0 font-mono text-[9px]">0 AP</span></button>
                </div>
              </section>
            </div>

            <section
              id="interrogation-workspace"
              class="mt-5 border-y border-[#91785c] bg-[#dccdad] px-3 py-4 sm:px-4"
              aria-labelledby="interrogation-heading"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">ARC interview desk</p>
                  <h3 id="interrogation-heading" class="mt-1 font-serif text-xl font-semibold">Suspect statement</h3>
                </div>
                <p id="interrogation-status" class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]" aria-live="polite">
                  {publicState.phase.replaceAll("_", " ")}
                </p>
              </div>

              {#if publicState.phase === "detective_turn" && availableActions.has("interrogate")}
                {#if latestStatement}
                  <div id="challenge-result" class="mt-4 border-l-4 border-[#8c3f33] bg-[#eadbbc] p-4" aria-live="polite">
                    <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7d6650]">Latest private note · {latestStatement.topic_code}</p>
                    <p class="mt-2 font-serif text-sm italic leading-6">“{latestStatement.response_text}”</p>
                    <p class="mt-2 font-mono text-[9px] uppercase tracking-[0.1em] text-[#8c3f33]">{latestStatement.resolution.replaceAll("_", " ")}</p>
                  </div>
                {/if}

                {#if selectedInterrogation}
                  <div class="mt-4 grid gap-4 sm:grid-cols-[0.8fr_1.2fr]">
                    <div class="border-l-2 border-[#9e4035] pl-3">
                      <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7b654d]">Subject</p>
                      <p class="mt-1 font-serif text-lg font-semibold">{selectedInterrogation.suspect_name}</p>
                      <p class="mt-2 text-xs leading-5 text-[#695642]">Choose one known case card. Free-form questions are not legal commands.</p>
                    </div>

                    <fieldset id="interrogation-topics">
                      <legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7b654d]">Known topics</legend>
                      <div class="mt-2 grid gap-2">
                        {#each selectedInterrogation.topics as topic}
                          <label
                            id={`interrogate-topic-${topic.id}`}
                            class={`flex min-h-11 cursor-pointer items-center gap-3 border px-3 py-2 transition ${selectedTopicId === topic.id ? "border-[#963a31] bg-[#f1e2c4]" : "border-[#9f896c] bg-[#e4d6b8] hover:bg-[#ecdec1]"}`}
                          >
                            <input type="radio" name="interrogation-topic" value={topic.id} bind:group={selectedTopicId} class="accent-[#963a31]" />
                            <span class="font-mono text-[10px] font-semibold text-[#963a31]">{topic.code}</span>
                            <span class="text-sm font-semibold">{topic.title}</span>
                          </label>
                        {/each}
                      </div>
                    </fieldset>
                  </div>

                  {#if selectedSuspectLeverage > 0}
                    <label class="mt-4 flex min-h-11 cursor-pointer items-center gap-3 border-t border-[#a48b6c] pt-3 text-xs">
                      <input type="checkbox" bind:checked={spendLeverage} class="accent-[#963a31]" />
                      Spend 1 leverage over this suspect to force the most useful response.
                    </label>
                  {/if}

                  <button
                    id="action-interrogate"
                    type="button"
                    disabled={!selectedTopic || commandPending}
                    onclick={submitInterrogation}
                    class="mt-4 min-h-11 w-full cursor-pointer bg-[#30261f] px-4 text-left text-sm font-semibold text-[#f5e7c9] transition hover:bg-[#49372a] disabled:cursor-not-allowed disabled:opacity-40"
                  >Question suspect <span class="float-right font-mono text-[10px]">1 AP</span></button>
                {:else}
                  <p class="mt-4 border-l-2 border-[#9e4035] pl-3 text-sm leading-6 text-[#65523f]">Select a highlighted suspect from the public file. You must share their location.</p>
                {/if}
              {:else if pendingPublic?.stage === "awaiting_chisel"}
                {#if privateState.role === "chisel" && pendingPrivate}
                  <div id="chisel-response-deck" class="mt-4">
                    <p class="text-sm leading-6 text-[#5f4b39]">
                      {pendingPrivate.detective.display_name} asks {pendingPrivate.suspect.name} about case card {pendingPrivate.topic.code}.
                    </p>
                    <fieldset class="mt-3">
                      <legend class="sr-only">Choose the suspect response</legend>
                      <div class="grid gap-2">
                        {#each pendingPrivate.response_options as response}
                          <label
                            id={`chisel-response-${response.id}`}
                            class={`cursor-pointer border-l-4 px-3 py-3 transition ${selectedResponseId === response.id ? "bg-[#f3e4c5]" : "bg-[#d2c09f] hover:bg-[#dfcead]"} ${response.type === "most_useful" ? "border-[#2f4b42]" : "border-[#9d3d34]"}`}
                          >
                            <span class="flex items-center justify-between gap-3">
                              <span class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#6f5944]">{response.type.replaceAll("_", " ")}</span>
                              <input type="radio" name="chisel-response" value={response.id} bind:group={selectedResponseId} class="accent-[#963a31]" />
                            </span>
                            <span class="mt-2 block font-serif text-sm leading-6">{response.text}</span>
                          </label>
                        {/each}
                      </div>
                    </fieldset>
                    <button
                      id="action-select-response"
                      type="button"
                      disabled={!selectedResponseId || commandPending}
                      onclick={submitResponse}
                      class="mt-3 min-h-11 w-full cursor-pointer bg-[#8f372f] px-4 text-sm font-semibold text-[#fff0d6] transition hover:bg-[#a84338] disabled:cursor-not-allowed disabled:opacity-40"
                    >Seal and deliver response</button>
                  </div>
                {:else}
                  <div class="mt-4 border border-dashed border-[#8e765b] bg-[#d3c19f] p-5 text-center">
                    <p class="font-serif text-lg italic">Statement requested</p>
                    <p class="mt-2 font-mono text-[9px] uppercase tracking-[0.12em] text-[#745f48]">Waiting for the Chisel to seal a response</p>
                  </div>
                {/if}
              {:else if pendingPublic?.stage === "awaiting_detective_decision"}
                <div id="published-response-card" class="relative mt-4 border border-[#806749] bg-[#efe0c0] p-4" tabindex="-1">
                  <span class="absolute right-3 top-3 font-mono text-[9px] uppercase tracking-[0.12em] text-[#963a31]">Statement · {pendingPublic.topic_code}</span>
                  {#if privateState.role === "detective" && pendingPrivate?.response_text}
                    <p class="max-w-xl pr-20 font-serif text-base italic leading-7">“{pendingPrivate.response_text}”</p>
                  {:else if privateState.role === "chisel" && pendingPrivate?.selected_response}
                    <p class="max-w-xl pr-20 font-serif text-base italic leading-7">“{pendingPrivate.selected_response.text}”</p>
                  {:else}
                    <p class="max-w-xl pr-20 font-serif text-base italic leading-7 text-[#76624c]">The statement is sealed for the questioning Detective.</p>
                  {/if}
                </div>

                {#if availableActions.has("accept_response") || availableActions.has("challenge_response")}
                  <div class="mt-3 grid grid-cols-2 gap-2">
                    <button
                      id="action-accept-response"
                      type="button"
                      disabled={!availableActions.has("accept_response") || commandPending}
                      onclick={() => sendCommand("accept_response", {})}
                      class="min-h-12 cursor-pointer border-2 border-[#344a40] bg-[#d6d2b5] font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-[#263c34] transition hover:bg-[#e5dfc1] disabled:cursor-not-allowed disabled:opacity-40"
                    >Accept statement</button>
                    <button
                      id="action-challenge-response"
                      type="button"
                      disabled={!availableActions.has("challenge_response") || commandPending}
                      onclick={() => sendCommand("challenge_response", {})}
                      class="min-h-12 cursor-pointer border-2 border-[#9b3d34] bg-[#e1c5a9] font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-[#812f29] transition hover:bg-[#ecd2b5] disabled:cursor-not-allowed disabled:opacity-40"
                    >Challenge · stake 1</button>
                  </div>
                {/if}
              {:else if latestStatement}
                <div id="challenge-result" class="mt-4 border-l-4 border-[#8c3f33] bg-[#eadbbc] p-4" aria-live="polite">
                  <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7d6650]">Latest private note · {latestStatement.topic_code}</p>
                  <p class="mt-2 font-serif text-sm italic leading-6">“{latestStatement.response_text}”</p>
                  <p class="mt-2 font-mono text-[9px] uppercase tracking-[0.1em] text-[#8c3f33]">{latestStatement.resolution.replaceAll("_", " ")}</p>
                </div>
              {:else}
                <p class="mt-4 text-sm leading-6 text-[#695642]">Move to a suspect, choose a known case card, and spend one action to question them.</p>
              {/if}
            </section>

            <section id="keyboard-location-list" class="mt-5 border-t border-[#a38b6e] pt-4" aria-labelledby="location-list-heading">
              <h3 id="location-list-heading" class="font-mono text-[10px] uppercase tracking-[0.14em] text-[#80694f]">Location index</h3>
              <div class="mt-2 grid gap-1 sm:grid-cols-2">
                {#each publicState.locations as location}
                  <button
                    id={`location-index-${location.id}`}
                    type="button"
                    onclick={() => locationAction(location)}
                    class={`cursor-pointer px-2 py-1.5 text-left text-xs transition ${legalLocation(location.id) ? "bg-[#a54235] text-[#fff0d6] hover:bg-[#b94d3f]" : "hover:bg-[#d4c4a5]"}`}
                  >
                    {location.name}
                    <span class="float-right font-mono text-[9px] uppercase">{legalLocation(location.id) ? "legal" : location.type.replaceAll("_", " ")}</span>
                  </button>
                {/each}
              </div>
            </section>
          </div>

          <aside id="chisel-hud" class="border-t border-[#a38b6e] bg-[#cab99a] p-4 xl:border-l xl:border-t-0" aria-labelledby="chisel-heading">
            <div class="flex items-center gap-3">
              <svg class="size-14 shrink-0 border border-[#533b2d] bg-[#231b17]" viewBox="0 0 64 64" role="img" aria-label="Original Chisel portrait token">
                <rect width="64" height="64" fill="#352720" />
                <path d="M12 25h40L44 12H21Z" fill="#111315" />
                <path d="M20 23c0 15 3 24 12 24s13-9 13-24Z" fill="#b18a68" />
                <path d="M18 64c2-14 7-20 14-20s14 6 16 20Z" fill="#7b3029" />
                <path d="M25 29h5m5 0h5" stroke="#1e1815" stroke-width="2" />
              </svg>
              <div class="min-w-0">
                <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#7e3029]">Chisel · case handler</p>
                <h2 id="chisel-heading" class="break-words font-serif text-base font-semibold leading-tight">{chisel?.display_name ?? "Unassigned"}</h2>
                <p class="mt-1 font-mono text-[9px] uppercase text-[#715d47]">No turn · reacts to Detective actions</p>
              </div>
            </div>

            {#if privateState.role === "chisel"}
              <div class="mt-5 border-y border-[#9d8669] py-4">
                <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#7e3029]">Private casebook</p>
                <p class="mt-2 font-serif text-sm italic leading-6 text-[#4e3d2f]">{privateState.casebook.briefing}</p>
                <dl class="mt-4 space-y-2 text-xs">
                  <div class="flex justify-between gap-3"><dt class="text-[#715d47]">Solution suspect</dt><dd class="font-mono font-semibold">{privateState.casebook.solution?.suspect_id ?? "—"}</dd></div>
                  <div class="flex justify-between gap-3"><dt class="text-[#715d47]">Leverage held</dt><dd class="font-mono font-semibold">{Object.values(privateState.leverage_by_detective).reduce((sum, value) => sum + value, 0)}</dd></div>
                  <div class="flex justify-between gap-3"><dt class="text-[#715d47]">Pending response</dt><dd class="font-mono font-semibold">{privateState.pending_interrogation ? "OPEN" : "NONE"}</dd></div>
                </dl>
              </div>
            {:else}
              <div class="mt-5 border-y border-[#9d8669] py-4 text-sm leading-6 text-[#5f4b39]">
                Chisel secrets remain on the private user channel. Detective clients never receive the solution or response matrix.
              </div>
            {/if}

            <div class="mt-4" aria-live="polite">
              <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#80694f]">Latest entry</p>
              <p class="mt-2 text-sm leading-5 text-[#4f3e30]">{lastEvent}</p>
            </div>

            {#if commandError}
              <div id="game-command-error" class="mt-4 border-l-2 border-[#a54235] bg-[#e1cfad] p-3 text-xs leading-5" role="alert">
                <p>{commandError}</p>
                {#if retryCommand}
                  <button type="button" onclick={retryLastCommand} class="mt-2 cursor-pointer font-semibold text-[#8e352d] underline underline-offset-2">Retry command</button>
                {/if}
              </div>
            {/if}
          </aside>
        </div>
      </section>
    </main>
  </div>
</div>
