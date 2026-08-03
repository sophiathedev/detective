<script>
  import { onDestroy, onMount } from "svelte"

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
  let blockedSnitchPlayerIds = $state([])
  let accusationSuspectId = $state(null)
  let accusationWeaponId = $state(null)
  let accusationMotiveId = $state(null)
  let spendLeverage = $state(false)
  let commandPending = $state(false)
  let retryCommand = $state(null)
  let commandError = $state(null)
  let lastEvent = $state("Casebook synchronized.")
  let mapIntent = $state(null)
  let lastTravel = $state(null)
  let onlinePlayerIds = $state([])
  let offlineDeadlines = $state({})
  let allPlayersOnline = $state(false)
  let connectionSnapshotReceived = $state(false)
  let connectionClock = $state(Date.now())
  let pauseDocument = $state(null)
  let previouslyFocusedElement = null
  let pauseActive = false
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
  let searchableSuspectIds = $derived(new Set(privateState.searchable_suspect_ids ?? []))
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
  let latestSearch = $derived(privateState.search_notes?.[0])
  let heldEvidence = $derived(privateState.evidence ?? [])
  let knownCaseCards = $derived(privateState.known_case_cards ?? [])
  let accusationOptions = $derived(
    privateState.accusation_options ?? { suspects: [], weapons: [], motives: [] },
  )
  let offlinePlayers = $derived(
    connectionSnapshotReceived
      ? publicState.players.filter((player) => !onlinePlayerIds.includes(player.id))
      : [],
  )
  let selectedSuspectLeverage = $derived(
    privateState.leverage_on_suspects?.[selectedSuspectId] ?? 0,
  )
  let travelPath = $derived.by(() => {
    if (!lastTravel?.from_location_id || !lastTravel?.location_id) return null

    const from = publicState.locations.find(
      (location) => location.id === lastTravel.from_location_id,
    )
    const destination = publicState.locations.find(
      (location) => location.id === lastTravel.location_id,
    )

    return from && destination ? { from, destination, key: lastTravel.key } : null
  })
  let mapStatus = $derived(
    privateState.role !== "detective"
      ? "Field map · only the active Detective can issue movement commands."
      : mapIntent
      ? `${mapIntent.type === "place" ? "Placing" : "Moving to"} ${locationName(mapIntent.locationId)}…`
      : ownPlayer?.location_id
        ? "Click a red-ringed location to spend 1 Move action."
        : "Choose any blue Police Station to enter the city for free.",
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

    const nextOwnPlayer = nextState.players.find(
      (player) => player.id === privateState.player_id,
    )

    if (mapIntent && nextOwnPlayer?.location_id === mapIntent.locationId) {
      mapIntent = null
    }

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
    if (!acceptEvent(message, seenPublicEventIds)) return false

    lastEvent = description
    return true
  }

  function locationAction(location) {
    selectedLocationId = location.id

    if (commandPending || connectionState !== "online") return

    if (placementLocationIds.has(location.id) && availableActions.has("place")) {
      mapIntent = { type: "place", locationId: location.id, commandId: null }
      sendCommand("place", { location_id: location.id })
    } else if (moveLocationIds.has(location.id) && availableActions.has("move")) {
      mapIntent = {
        type: "move",
        locationId: location.id,
        fromLocationId: ownPlayer?.location_id,
        commandId: null,
      }
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

    if (mapIntent && (type === "place" || type === "move")) {
      mapIntent = { ...mapIntent, commandId: command.command_id }
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
        if (mapIntent?.commandId === command.command_id) mapIntent = null
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
      search_not_available: "This case has no Search card for that target.",
      search_archived: "That Search card was archived and cannot be used again.",
      evidence_not_takeable: "That Case card cannot be taken as evidence.",
      evidence_unavailable: "That evidence is already held or faceup.",
      free_question_pending: "Ask the newly discovered suspect now, or decline the free question.",
      free_question_not_available: "No immediate free question is waiting.",
      question_block_unavailable: "No matching Chisel leverage remains to block this question.",
      question_not_blocked: "This question is not waiting on a goon decision.",
      insufficient_scratch: "You do not have enough Scratch for that bribe.",
      not_snitch_eligible: "You are not eligible to Snitch on this question.",
      snitch_choice_recorded: "Your facedown Snitch choice is already locked.",
      invalid_snitch_resolution: "The selected Snitch blocks are not legal.",
      insufficient_chisel_leverage: "The Chisel lacks matching leverage for one of those blocks.",
      accusation_not_available: "This case has no validated accusation sheet.",
      invalid_accusation: "Choose one valid suspect, weapon, and motive.",
      accusation_must_start_turn: "The Solve token may be used only before spending an action.",
      solve_token_spent: "Your one Solve token has already been spent.",
      accusation_suspect_unknown: "That suspect has not been revealed.",
      accusation_weapon_unknown: "That possible weapon has not been discovered.",
      final_guess_already_submitted: "Your final guess is already sealed.",
      game_paused: "The case is sealed while a player is offline.",
      game_not_paused: "The case is not paused.",
      players_offline: "Every player must reconnect before the Chisel resumes.",
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

  function disconnectCountdown(playerId) {
    const deadline = offlineDeadlines[playerId]
    const remainingMilliseconds = deadline ? deadline - connectionClock : 0

    if (remainingMilliseconds <= 0) return "PAUSED"

    const remainingSeconds = Math.ceil(remainingMilliseconds / 1000)
    const minutes = Math.floor(remainingSeconds / 60)
    const seconds = remainingSeconds % 60

    return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
  }

  function restorePreviousFocus() {
    const focusTarget = previouslyFocusedElement
    previouslyFocusedElement = null

    window.requestAnimationFrame(() => {
      if (
        focusTarget?.isConnected &&
        !focusTarget.closest("[inert]") &&
        typeof focusTarget.focus === "function"
      ) {
        focusTarget.focus({ preventScroll: true })
      }
    })
  }

  $effect(() => {
    const paused = publicState.status === "paused"

    if (paused === pauseActive) return

    pauseActive = paused

    if (paused) {
      previouslyFocusedElement = document.activeElement

      window.requestAnimationFrame(() => {
        if (publicState.status === "paused" && pauseDocument?.isConnected) {
          pauseDocument.focus({ preventScroll: true })
        }
      })
    } else {
      restorePreviousFocus()
    }
  })

  onDestroy(() => {
    if (typeof window !== "undefined" && pauseActive) restorePreviousFocus()
  })

  function selectSuspect(suspectId) {
    if (
      (!interrogatableSuspectIds.has(suspectId) && !searchableSuspectIds.has(suspectId)) ||
      commandPending
    )
      return

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

  function submitSuspectSearch() {
    if (!selectedSuspectId || !searchableSuspectIds.has(selectedSuspectId)) return
    sendCommand("search_suspect", { suspect_id: selectedSuspectId })
  }

  function submitResponse() {
    if (!selectedResponseId || !pendingPrivate?.id) return
    sendCommand("select_response", { response_id: selectedResponseId })
  }

  function submitSnitchResolution() {
    const requestIds = new Set(pendingPrivate?.snitch_requests?.map((request) => request.player_id) ?? [])
    const blockedPlayerIds = blockedSnitchPlayerIds.filter((playerId) => requestIds.has(playerId))
    sendCommand("resolve_snitches", { blocked_player_ids: blockedPlayerIds })
  }

  function submitAccusation() {
    if (!accusationSuspectId || !accusationWeaponId || !accusationMotiveId) return

    const commandType = availableActions.has("accuse")
      ? "accuse"
      : availableActions.has("submit_final_guess")
        ? "submit_final_guess"
        : null

    if (!commandType) return

    sendCommand(commandType, {
      suspect_id: accusationSuspectId,
      weapon_id: accusationWeaponId,
      motive_id: accusationMotiveId,
    })
  }

  function invalidateConnectionSnapshot() {
    connectionState = "offline"
    connectionSnapshotReceived = false
    onlinePlayerIds = []
    offlineDeadlines = {}
    allPlayersOnline = false
  }

  onMount(() => {
    const connectionClockInterval = window.setInterval(() => {
      connectionClock = Date.now()
    }, 1000)
    const socket = window.getGameSocket?.()
    if (!socket) {
      connectionState = "offline"
      return () => window.clearInterval(connectionClockInterval)
    }

    gameChannel = socket.channel(`game:${game_id}`, {})
    userChannel = socket.channel(`user:${user_id}`, { game_id })

    gameChannel.onError(invalidateConnectionSnapshot)
    gameChannel.onClose(invalidateConnectionSnapshot)

    gameChannel.on("game_state", ({ state }) => applyPublic(state))
    gameChannel.on("connection_state", (state) => {
      onlinePlayerIds = state.online_player_ids
      offlineDeadlines = state.offline_deadlines
      allPlayersOnline = state.all_players_online
      connectionSnapshotReceived = true
      connectionState = "online"
    })
    gameChannel.on("game_paused", (message) =>
      recordPublicEvent(message, "A missing investigator sealed the case."),
    )
    gameChannel.on("game_resumed", (message) =>
      recordPublicEvent(message, "Every investigator returned. The case reopened."),
    )
    gameChannel.on("detective_placed", (message) =>
      recordPublicEvent(message, "A Detective entered the city."),
    )
    gameChannel.on("player_moved", (message) => {
      if (recordPublicEvent(message, "A Detective moved to a new location.")) {
        lastTravel = {
          ...message.payload,
          key: message.event_id ?? `${message.version}-${message.payload.player_id}`,
        }
      }
    })
    gameChannel.on("evidence_analyzed", (message) =>
      recordPublicEvent(message, "Evidence was analyzed."),
    )
    gameChannel.on("kickback_collected", (message) =>
      recordPublicEvent(message, "A contact paid out a kickback."),
    )
    gameChannel.on("location_searched", (message) =>
      recordPublicEvent(message, "A Detective searched the current location."),
    )
    gameChannel.on("suspect_searched", (message) =>
      recordPublicEvent(message, "A Detective searched a suspect."),
    )
    gameChannel.on("evidence_submitted", (message) =>
      recordPublicEvent(message, "Held evidence returned to the public casefile."),
    )
    gameChannel.on("free_question_declined", (message) =>
      recordPublicEvent(message, "The immediate question was declined."),
    )
    gameChannel.on("question_allowed", (message) =>
      recordPublicEvent(message, "The Chisel allowed the question to proceed."),
    )
    gameChannel.on("question_blocked", (message) =>
      recordPublicEvent(message, "The Chisel sent a goon to block the question."),
    )
    gameChannel.on("question_abandoned", (message) =>
      recordPublicEvent(message, "The blocked question was abandoned."),
    )
    gameChannel.on("goon_bribed", (message) =>
      recordPublicEvent(message, "The Detective paid the goon and restored the question."),
    )
    gameChannel.on("snitch_decision_recorded", (message) =>
      recordPublicEvent(message, "A facedown Snitch decision was filed."),
    )
    gameChannel.on("snitch_window_closed", (message) =>
      recordPublicEvent(message, "All Snitch decisions were revealed."),
    )
    gameChannel.on("snitches_resolved", (message) =>
      recordPublicEvent(message, "The Chisel resolved the revealed Snitch requests."),
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
    gameChannel.on("accusation_submitted", (message) =>
      recordPublicEvent(message, "A Detective submitted a Solve accusation."),
    )
    gameChannel.on("accusation_rejected", (message) =>
      recordPublicEvent(message, "A Solve accusation was incorrect."),
    )
    gameChannel.on("final_guess_submitted", (message) =>
      recordPublicEvent(message, "A sealed final guess entered the casefile."),
    )
    gameChannel.on("game_finished", (message) =>
      recordPublicEvent(message, "The case is closed and the solution is public."),
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
      } else if (payload.type === "search_result") {
        lastEvent = payload.free_question_suspect_id
          ? "Search complete. A newly discovered suspect may be questioned for free."
          : "Search complete. The private result is filed in your notebook."
      } else if (payload.type === "snitch_choice_recorded") {
        lastEvent = payload.snitch
          ? "Your Snitch marker is facedown. Other players cannot see the choice yet."
          : "You passed on this Snitch opportunity."
      } else if (payload.type === "snitch_resolved") {
        lastEvent = payload.blocked
          ? "The Chisel spent leverage to block your Snitch. No Scratch was charged."
          : "Your Snitch succeeded. The final response will arrive after the decision."
      } else if (payload.type === "snitch_result") {
        lastEvent = "The final response reached your private notebook for $3 Scratch."
      } else if (payload.type === "accusation_result") {
        lastEvent = payload.solved
          ? "Your accusation solved all three parts of the case."
          : `${payload.correct_count} of 3 accusation elements were correct.`
      } else if (payload.type === "final_guess_recorded") {
        lastEvent = "Your final guess is sealed until every Detective submits."
      }
    })

    gameChannel
      .join()
      .receive("ok", ({ state }) => {
        applyPublic(state)
      })
      .receive("error", () => (connectionState = "unauthorized"))
      .receive("timeout", () => (connectionState = "offline"))

    userChannel
      .join()
      .receive("ok", ({ state, version }) => applyPrivate(state, version))
      .receive("error", () => (connectionState = "unauthorized"))

    return () => {
      window.clearInterval(connectionClockInterval)
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
      <div
        id="game-casebook-workspace"
        class="contents"
        inert={publicState.status === "paused"}
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
            <p class="mt-1">Active: {activeDetective?.display_name ?? "-"}</p>
          </div>
        </div>

        <div class="relative overflow-hidden bg-[#b7a78b] p-2 sm:p-3">
          <div
            id="map-command-status"
            class={`pointer-events-none absolute left-4 top-4 z-10 max-w-[18rem] border px-3 py-2 font-mono text-[9px] uppercase tracking-[0.1em] shadow-[0_8px_24px_rgba(35,24,16,0.22)] sm:left-5 sm:top-5 ${mapIntent ? "map-command-pending border-[#8e342d] bg-[#f1dec0] text-[#7d2e28]" : "border-[#776149] bg-[#e8dcc3]/95 text-[#5d4b38]"}`}
            aria-live="polite"
            aria-busy={mapIntent !== null}
          >
            {mapStatus}
          </div>
          <svg
            id="game-map"
            class="game-map-board aspect-[2048/1331] w-full select-none border border-[#6e5c48] bg-[#c9b998]"
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

            {#if travelPath}
              {#key travelPath.key}
                <g id="latest-travel-trace" class="map-travel-trace" aria-hidden="true">
                  <line
                    x1={travelPath.from.x * 2048}
                    y1={travelPath.from.y * 1331}
                    x2={travelPath.destination.x * 2048}
                    y2={travelPath.destination.y * 1331}
                    pathLength="1"
                    class="map-travel-line"
                    vector-effect="non-scaling-stroke"
                  />
                  <circle
                    cx={travelPath.destination.x * 2048}
                    cy={travelPath.destination.y * 1331}
                    r="48"
                    class="map-arrival-pulse"
                    vector-effect="non-scaling-stroke"
                  />
                </g>
              {/key}
            {/if}

            <g id="map-locations">
              {#each publicState.locations as location}
                <g
                  id={`map-location-${location.id}`}
                  transform={`translate(${location.x * 2048} ${location.y * 1331})`}
                  class={`map-location-marker ${legalLocation(location.id) ? "map-location-legal cursor-pointer" : "cursor-default"} ${mapIntent?.locationId === location.id ? "map-location-pending" : ""}`}
                  role="button"
                  tabindex="0"
                  aria-label={locationLabel(location)}
                  aria-disabled={!legalLocation(location.id)}
                  aria-busy={mapIntent?.locationId === location.id}
                  onclick={() => locationAction(location)}
                  onkeydown={(event) => locationKeydown(event, location)}
                >
                  {#if legalLocation(location.id)}
                    <circle class="map-legal-ring" r="42" fill="none" stroke="#c94f3e" stroke-width="7" />
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
                  <g
                    id={`detective-map-token-${detective.id}`}
                    class={`map-detective-token ${lastTravel?.player_id === detective.id ? "map-detective-token-active" : ""}`}
                    style={`transform: translate(${tokenLocation.x * 2048 + (detective.seat - 1) * 22}px, ${tokenLocation.y * 1331 - 28}px);`}
                  >
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
                  disabled={(!interrogatableSuspectIds.has(suspect.id) && !searchableSuspectIds.has(suspect.id)) || commandPending}
                  aria-pressed={selectedSuspectId === suspect.id}
                  onclick={() => selectSuspect(suspect.id)}
                  class={`flex min-h-14 items-center gap-2 border p-2 text-left transition ${selectedSuspectId === suspect.id ? "border-[#8f342d] bg-[#f0dfbd] ring-2 ring-[#a54235]" : "border-[#a18a6d] bg-[#e6d9bd]"} ${interrogatableSuspectIds.has(suspect.id) || searchableSuspectIds.has(suspect.id) ? "cursor-pointer hover:bg-[#f2e4c8]" : "cursor-default"}`}
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
                    {#if connectionSnapshotReceived && !onlinePlayerIds.includes(detective.id)}
                      <span
                        id={`detective-connection-${seat}`}
                        class="detective-offline-mark"
                        role="timer"
                        aria-label={`${detective.display_name} offline, pause countdown ${disconnectCountdown(detective.id)}`}
                      >OFFLINE · {disconnectCountdown(detective.id)}</span>
                    {/if}
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
                <dl class="grid grid-cols-2 gap-4 text-right sm:grid-cols-4">
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
                  <div>
                    <dt class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#80694f]">Solve</dt>
                    <dd class="mt-1 font-mono text-sm font-semibold">{privateState.solve_token_available ? "READY" : "SPENT"}</dd>
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
                    id="action-search-location"
                    type="button"
                    disabled={!availableActions.has("search_location") || commandPending}
                    onclick={() => sendCommand("search_location", {})}
                    class="flex min-h-10 cursor-pointer items-center justify-between gap-2 border border-[#796349] bg-[#efe2c5] px-3 text-left text-sm font-semibold transition hover:bg-[#f8ecd2] disabled:cursor-not-allowed disabled:opacity-35"
                  >Search location <span class="shrink-0 font-mono text-[9px]">1 AP</span></button>
                  <button
                    id="action-search-suspect"
                    type="button"
                    disabled={!selectedSuspectId || !searchableSuspectIds.has(selectedSuspectId) || commandPending}
                    onclick={submitSuspectSearch}
                    class="flex min-h-10 cursor-pointer items-center justify-between gap-2 border border-[#796349] bg-[#efe2c5] px-3 text-left text-sm font-semibold transition hover:bg-[#f8ecd2] disabled:cursor-not-allowed disabled:opacity-35"
                  >Search suspect <span class="shrink-0 font-mono text-[9px]">1 AP</span></button>
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
                    id="action-skip-free-question"
                    type="button"
                    disabled={!availableActions.has("skip_free_question") || commandPending}
                    onclick={() => sendCommand("skip_free_question", {})}
                    class="flex min-h-10 cursor-pointer items-center justify-between gap-2 border border-[#796349] bg-[#d7c7aa] px-3 text-left text-sm font-semibold transition hover:bg-[#e7d8bb] disabled:hidden"
                  >Decline free question <span class="shrink-0 font-mono text-[9px]">0 AP</span></button>
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
                  >Question suspect <span class="float-right font-mono text-[10px]">{privateState.free_question_suspect_id ? "FREE" : "1 AP"}</span></button>
                {:else}
                  <p class="mt-4 border-l-2 border-[#9e4035] pl-3 text-sm leading-6 text-[#65523f]">Select a highlighted suspect from the public file. You must share their location.</p>
                {/if}
              {:else if pendingPublic?.stage === "awaiting_chisel_block"}
                {#if privateState.role === "chisel" && pendingPrivate}
                  <div id="chisel-block-decision" class="mt-4 border-l-4 border-[#71372f] bg-[#d3c19f] p-4">
                    <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">Chisel leverage window</p>
                    <p class="mt-2 text-sm leading-6 text-[#5f4b39]">
                      {pendingPrivate.detective.display_name} asks {pendingPrivate.suspect.name} about case card {pendingPrivate.topic.code}.
                    </p>
                    <div class="mt-3 grid gap-2 sm:grid-cols-2">
                      <button
                        id="action-allow-question"
                        type="button"
                        disabled={!availableActions.has("allow_question") || commandPending}
                        onclick={() => sendCommand("allow_question", {})}
                        class="min-h-11 cursor-pointer border-2 border-[#344a40] bg-[#d6d2b5] px-3 text-sm font-semibold text-[#263c34] transition hover:bg-[#e5dfc1] disabled:cursor-not-allowed disabled:opacity-40"
                      >Allow question</button>
                      <button
                        id="action-block-question"
                        type="button"
                        disabled={!availableActions.has("block_question") || commandPending}
                        onclick={() => sendCommand("block_question", {})}
                        class="min-h-11 cursor-pointer border-2 border-[#9b3d34] bg-[#e1c5a9] px-3 text-sm font-semibold text-[#812f29] transition hover:bg-[#ecd2b5] disabled:cursor-not-allowed disabled:opacity-40"
                      >Spend matching leverage to block</button>
                    </div>
                  </div>
                {:else}
                  <div class="mt-4 border border-dashed border-[#8e765b] bg-[#d3c19f] p-5 text-center">
                    <p class="font-serif text-lg italic">Question under review</p>
                    <p class="mt-2 font-mono text-[9px] uppercase tracking-[0.12em] text-[#745f48]">Waiting for the Chisel's leverage decision</p>
                  </div>
                {/if}
              {:else if pendingPublic?.stage === "question_blocked"}
                <div id="blocked-question-card" class="mt-4 border-l-4 border-[#9b3d34] bg-[#e1c5a9] p-4">
                  <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#812f29]">Question blocked</p>
                  <p class="mt-2 text-sm leading-6 text-[#5f4b39]">The action remains spent. The questioning Detective may abandon the question or pay $2 Scratch to bribe the goon.</p>
                  {#if availableActions.has("accept_question_block") || availableActions.has("bribe_goon")}
                    <div class="mt-3 grid gap-2 sm:grid-cols-2">
                      <button
                        id="action-accept-question-block"
                        type="button"
                        disabled={!availableActions.has("accept_question_block") || commandPending}
                        onclick={() => sendCommand("accept_question_block", {})}
                        class="min-h-11 cursor-pointer border border-[#796349] bg-[#d7c7aa] px-3 text-sm font-semibold transition hover:bg-[#e7d8bb] disabled:cursor-not-allowed disabled:opacity-40"
                      >Abandon question</button>
                      <button
                        id="action-bribe-goon"
                        type="button"
                        disabled={!availableActions.has("bribe_goon") || commandPending}
                        onclick={() => sendCommand("bribe_goon", {})}
                        class="min-h-11 cursor-pointer bg-[#8f372f] px-3 text-sm font-semibold text-[#fff0d6] transition hover:bg-[#a84338] disabled:cursor-not-allowed disabled:opacity-40"
                      >Pay $2 and proceed</button>
                    </div>
                  {/if}
                </div>
              {:else if pendingPublic?.stage === "awaiting_snitches"}
                <div id="snitch-window" class="mt-4 border-y border-[#8e765b] bg-[#d3c19f] p-4">
                  <div class="flex items-center justify-between gap-3">
                    <div>
                      <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#812f29]">Facedown informants</p>
                      <p class="mt-1 font-serif text-lg font-semibold">Snitch window</p>
                    </div>
                    <p class="font-mono text-[9px] uppercase tracking-[0.1em] text-[#725e48]">{pendingPublic.snitch_decisions_recorded}/{pendingPublic.snitch_decisions_required} filed</p>
                  </div>
                  {#if availableActions.has("choose_snitch") || availableActions.has("decline_snitch")}
                    <p class="mt-3 text-sm leading-6 text-[#5f4b39]">Your choice remains hidden until every eligible Detective files a marker. An allowed Snitch costs $3 only after the final response.</p>
                    <div class="mt-3 grid grid-cols-2 gap-2">
                      <button
                        id="action-decline-snitch"
                        type="button"
                        disabled={!availableActions.has("decline_snitch") || commandPending}
                        onclick={() => sendCommand("decline_snitch", {})}
                        class="min-h-11 cursor-pointer border border-[#796349] bg-[#d7c7aa] px-3 text-sm font-semibold transition hover:bg-[#e7d8bb] disabled:cursor-not-allowed disabled:opacity-40"
                      >Pass</button>
                      <button
                        id="action-choose-snitch"
                        type="button"
                        disabled={!availableActions.has("choose_snitch") || commandPending}
                        onclick={() => sendCommand("choose_snitch", {})}
                        class="min-h-11 cursor-pointer bg-[#30261f] px-3 text-sm font-semibold text-[#f5e7c9] transition hover:bg-[#49372a] disabled:cursor-not-allowed disabled:opacity-40"
                      >Place Snitch facedown</button>
                    </div>
                  {:else}
                    <p class="mt-3 text-sm leading-6 text-[#5f4b39]">Waiting for all eligible Detectives to lock their private choice.</p>
                  {/if}
                </div>
              {:else if pendingPublic?.stage === "awaiting_chisel_snitch_block"}
                {#if privateState.role === "chisel" && pendingPrivate}
                  <div id="chisel-snitch-blocks" class="mt-4 border-l-4 border-[#71372f] bg-[#d3c19f] p-4">
                    <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">Revealed Snitch markers</p>
                    <p class="mt-2 text-sm leading-6 text-[#5f4b39]">Spend one matching leverage marker for each informant you want to block.</p>
                    <fieldset class="mt-3 grid gap-2">
                      <legend class="sr-only">Choose Snitches to block</legend>
                      {#each pendingPrivate.snitch_requests as request}
                        <label id={`snitch-block-${request.player_id}`} class="flex min-h-11 cursor-pointer items-center justify-between gap-3 border border-[#8e765b] bg-[#e5d6b8] px-3 py-2">
                          <span class="text-sm font-semibold">{request.display_name}</span>
                          <span class="flex items-center gap-2 font-mono text-[9px] uppercase text-[#725e48]">
                            {request.can_block ? "block" : "no leverage"}
                            <input type="checkbox" value={request.player_id} bind:group={blockedSnitchPlayerIds} disabled={!request.can_block} class="accent-[#963a31]" />
                          </span>
                        </label>
                      {/each}
                    </fieldset>
                    <button
                      id="action-resolve-snitches"
                      type="button"
                      disabled={!availableActions.has("resolve_snitches") || commandPending}
                      onclick={submitSnitchResolution}
                      class="mt-3 min-h-11 w-full cursor-pointer bg-[#8f372f] px-4 text-sm font-semibold text-[#fff0d6] transition hover:bg-[#a84338] disabled:cursor-not-allowed disabled:opacity-40"
                    >Resolve Snitches and open response deck</button>
                  </div>
                {:else}
                  <div class="mt-4 border border-dashed border-[#8e765b] bg-[#d3c19f] p-5 text-center">
                    <p class="font-serif text-lg italic">Snitch markers revealed</p>
                    <p class="mt-2 font-mono text-[9px] uppercase tracking-[0.12em] text-[#745f48]">Waiting for the Chisel to spend matching leverage</p>
                  </div>
                {/if}
              {:else if pendingPublic?.stage === "awaiting_chisel_response"}
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

            {#if publicState.result}
              <section id="case-closed-result" class="mt-5 border-2 border-[#71372f] bg-[#eadbbc] p-4 sm:p-5" aria-labelledby="case-result-heading">
                <div class="flex flex-wrap items-start justify-between gap-4 border-b border-[#9d8669] pb-4">
                  <div>
                    <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Case closed</p>
                    <h3 id="case-result-heading" class="mt-1 font-serif text-2xl font-semibold">The sealed solution</h3>
                  </div>
                  <p class="font-mono text-[10px] uppercase tracking-[0.12em] text-[#71372f]">Winner: {publicState.result.winner.role}</p>
                </div>
                <dl class="mt-4 grid gap-3 sm:grid-cols-3">
                  <div class="border-l-2 border-[#71372f] pl-3"><dt class="font-mono text-[9px] uppercase text-[#725e48]">Suspect</dt><dd class="mt-1 font-serif text-base font-semibold">{publicState.result.solution.suspect_name}</dd></div>
                  <div class="border-l-2 border-[#71372f] pl-3"><dt class="font-mono text-[9px] uppercase text-[#725e48]">Weapon</dt><dd class="mt-1 font-serif text-base font-semibold">{publicState.result.solution.weapon_label}</dd></div>
                  <div class="border-l-2 border-[#71372f] pl-3"><dt class="font-mono text-[9px] uppercase text-[#725e48]">Motive</dt><dd class="mt-1 font-serif text-base font-semibold">{publicState.result.solution.motive_label}</dd></div>
                </dl>
                {#if publicState.result.epilogue}<p class="mt-4 max-w-3xl font-serif text-sm italic leading-6 text-[#4f3e30]">{publicState.result.epilogue}</p>{/if}
              </section>
            {:else if privateState.role === "detective" && accusationOptions.motives.length > 0 && (availableActions.has("accuse") || availableActions.has("submit_final_guess") || privateState.solve_attempt || privateState.final_guess || publicState.phase === "accusation")}
              <section id="accusation-sheet" class="mt-5 border-2 border-[#71372f] bg-[#d7c6a6] p-4" aria-labelledby="accusation-heading">
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Sealed deduction</p>
                    <h3 id="accusation-heading" class="mt-1 font-serif text-xl font-semibold">Suspect, weapon, motive</h3>
                  </div>
                  <span class="border border-[#8c3f33] px-2 py-1 font-mono text-[9px] uppercase tracking-[0.1em] text-[#8c3f33]">
                    {publicState.phase === "accusation" ? "final guess" : "solve token"}
                  </span>
                </div>

                {#if privateState.solve_attempt}
                  <p id="solve-attempt-result" class="mt-3 border-l-4 border-[#8c3f33] bg-[#eadbbc] p-3 text-sm font-semibold">
                    {privateState.solve_attempt.correct_count} of 3 elements were correct. The token is spent; your turn continues.
                  </p>
                {/if}

                {#if privateState.final_guess && publicState.phase === "accusation"}
                  <p id="final-guess-sealed" class="mt-3 border border-dashed border-[#8e765b] p-4 text-center font-serif text-sm italic">Your final guess is sealed. Waiting for the remaining Detectives.</p>
                {:else}
                  <div class="mt-4 grid gap-4 lg:grid-cols-3">
                    <fieldset id="accusation-suspects">
                      <legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">1 / Suspect</legend>
                      <div class="mt-2 grid gap-2">
                        {#each accusationOptions.suspects as suspect}
                          <label class={`flex min-h-11 cursor-pointer items-center gap-3 border px-3 py-2 ${accusationSuspectId === suspect.id ? "border-[#8c3f33] bg-[#f0dfbd]" : "border-[#9d8669] bg-[#e4d6b8]"}`}>
                            <input type="radio" name="accusation-suspect" value={suspect.id} bind:group={accusationSuspectId} class="accent-[#963a31]" />
                            <span class="text-sm font-semibold">{suspect.name}</span>
                          </label>
                        {/each}
                      </div>
                    </fieldset>

                    <fieldset id="accusation-weapons">
                      <legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">2 / Known weapon</legend>
                      <div class="mt-2 grid gap-2">
                        {#each accusationOptions.weapons as weapon}
                          <label class={`flex min-h-11 cursor-pointer items-center gap-3 border px-3 py-2 ${accusationWeaponId === weapon.id ? "border-[#8c3f33] bg-[#f0dfbd]" : "border-[#9d8669] bg-[#e4d6b8]"}`}>
                            <input type="radio" name="accusation-weapon" value={weapon.id} bind:group={accusationWeaponId} class="accent-[#963a31]" />
                            <span class="text-sm font-semibold">{weapon.label}</span>
                          </label>
                        {/each}
                      </div>
                    </fieldset>

                    <fieldset id="accusation-motives">
                      <legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">3 / Motive</legend>
                      <div class="mt-2 grid gap-2">
                        {#each accusationOptions.motives as motive}
                          <label class={`flex min-h-11 cursor-pointer items-center gap-3 border px-3 py-2 ${accusationMotiveId === motive.id ? "border-[#8c3f33] bg-[#f0dfbd]" : "border-[#9d8669] bg-[#e4d6b8]"}`}>
                            <input type="radio" name="accusation-motive" value={motive.id} bind:group={accusationMotiveId} class="accent-[#963a31]" />
                            <span class="text-sm font-semibold">{motive.label}</span>
                          </label>
                        {/each}
                      </div>
                    </fieldset>
                  </div>

                  <button
                    id="action-submit-accusation"
                    type="button"
                    disabled={(!availableActions.has("accuse") && !availableActions.has("submit_final_guess")) || !accusationSuspectId || !accusationWeaponId || !accusationMotiveId || commandPending}
                    onclick={submitAccusation}
                    class="mt-4 min-h-12 w-full cursor-pointer bg-[#8f372f] px-4 text-sm font-semibold text-[#fff0d6] transition hover:bg-[#a84338] disabled:cursor-not-allowed disabled:opacity-40"
                  >{publicState.phase === "accusation" ? "Seal final guess" : "Spend Solve token"}</button>
                  {#if publicState.phase !== "accusation"}<p class="mt-2 text-xs leading-5 text-[#695642]">A Solve accusation is legal only at the beginning of your turn, before any action is spent.</p>{/if}
                {/if}
              </section>
            {/if}

            {#if privateState.role === "detective"}
              <section id="private-evidence-dossier" class="mt-5 border-y border-[#91785c] bg-[#d4c3a3] px-3 py-4 sm:px-4" aria-labelledby="evidence-dossier-heading">
                <div class="flex flex-wrap items-end justify-between gap-3">
                  <div>
                    <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Private folio</p>
                    <h3 id="evidence-dossier-heading" class="mt-1 font-serif text-xl font-semibold">Search notes and evidence</h3>
                  </div>
                  <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#705b45]">{heldEvidence.length} held / {knownCaseCards.length} known</p>
                </div>

                <div class="mt-4 grid gap-3 sm:grid-cols-[minmax(0,1.1fr)_minmax(12rem,0.9fr)]">
                  <article id="latest-search-note" class="min-h-28 border-l-4 border-[#71372f] bg-[#eadbbc] p-3">
                    {#if latestSearch}
                      <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">Day {latestSearch.day} / {latestSearch.target_type.replaceAll("_", " ")}</p>
                      <p class="mt-2 font-serif text-sm italic leading-6">“{latestSearch.text}”</p>
                    {:else}
                      <p class="font-serif text-sm italic leading-6 text-[#725e48]">No private Search card has been filed.</p>
                    {/if}
                  </article>

                  <div id="held-evidence-list" class="grid content-start gap-2">
                    {#each heldEvidence as card}
                      <article id={`held-evidence-${card.id}`} class="border border-[#8b7257] bg-[#efe0c0] px-3 py-2">
                        <div class="flex items-center justify-between gap-3">
                          <span class="font-mono text-[10px] font-semibold text-[#8c3f33]">{card.code}</span>
                          <span class="font-mono text-[8px] uppercase tracking-[0.1em] text-[#725e48]">held evidence</span>
                        </div>
                        <h4 class="mt-1 font-serif text-sm font-semibold">{card.title}</h4>
                        {#if card.description}<p class="mt-1 text-[11px] leading-4 text-[#695642]">{card.description}</p>{/if}
                      </article>
                    {:else}
                      <p class="border border-dashed border-[#8b7257] p-3 text-xs leading-5 text-[#725e48]">No Case card is currently held as evidence.</p>
                    {/each}
                  </div>
                </div>
              </section>
            {/if}

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
                <span
                  id="chisel-connection-state"
                  class={[
                    "mt-1 block font-mono text-[9px] font-semibold uppercase tracking-[0.1em]",
                    !connectionSnapshotReceived
                      ? "text-[#715d47]"
                      : chisel && onlinePlayerIds.includes(chisel.id)
                        ? "text-[#315344]"
                        : "text-[#973b32]",
                  ]}
                  role="timer"
                  aria-label={`Chisel connection status: ${!connectionSnapshotReceived ? "syncing" : chisel && onlinePlayerIds.includes(chisel.id) ? "online" : `offline, pause countdown ${disconnectCountdown(chisel?.id)}`}`}
                >
                  {#if !connectionSnapshotReceived}
                    SYNCING
                  {:else if chisel && onlinePlayerIds.includes(chisel.id)}
                    ONLINE
                  {:else}
                    OFFLINE · {disconnectCountdown(chisel?.id)}
                  {/if}
                </span>
              </div>
            </div>

            {#if privateState.role === "chisel"}
              <div class="mt-5 border-y border-[#9d8669] py-4">
                <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#7e3029]">Private casebook</p>
                <p class="mt-2 font-serif text-sm italic leading-6 text-[#4e3d2f]">{privateState.casebook.briefing}</p>
                <dl class="mt-4 space-y-2 text-xs">
                  <div class="flex justify-between gap-3"><dt class="text-[#715d47]">Solution suspect</dt><dd class="font-mono font-semibold">{privateState.casebook.solution?.suspect_id ?? "-"}</dd></div>
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

            {#if commandError && publicState.status !== "paused"}
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
      </div>

      {#if publicState.status === "paused"}
        <section
          id="game-pause-seal"
          class="game-pause-seal"
          role="status"
          aria-labelledby="game-pause-heading"
          aria-describedby="game-pause-description"
        >
          <div
            id="game-pause-document"
            class="game-pause-document"
            role="document"
            tabindex="-1"
            bind:this={pauseDocument}
          >
            <p class="game-pause-kicker">Case sealed</p>
            <h2 id="game-pause-heading" class="mt-2 font-serif text-3xl font-semibold tracking-[-0.025em] sm:text-4xl">
              Investigation paused
            </h2>
            <p id="game-pause-description" class="mt-3 font-serif text-base italic leading-7">
              Waiting for every investigator to return.
            </p>

            <div class="game-pause-ledger">
              <span>Connection ledger</span>
              <strong>
                {connectionSnapshotReceived
                  ? allPlayersOnline
                    ? "All investigators present"
                    : `${offlinePlayers.length} ${offlinePlayers.length === 1 ? "investigator" : "investigators"} absent`
                  : "Synchronizing presence"}
              </strong>
            </div>

            <p class="game-pause-provenance">
              Seal record · {publicState.pause?.player_ids?.length ?? 0} disconnected · held from
              {publicState.pause?.previous_phase?.replaceAll("_", " ") ?? "active investigation"}
            </p>

            {#if commandError}
              <div id="game-pause-command-error" class="game-pause-command-error" role="alert">
                <p>{commandError}</p>
                {#if retryCommand?.type === "resume_game"}
                  <button
                    id="action-retry-resume-game"
                    type="button"
                    onclick={retryLastCommand}
                  >Retry resume</button>
                {/if}
              </div>
            {/if}

            {#if privateState.role === "chisel"}
              <button
                id="action-resume-game"
                type="button"
                disabled={!allPlayersOnline || !availableActions.has("resume_game") || commandPending}
                onclick={() => sendCommand("resume_game", {})}
              >Resume investigation</button>
            {/if}
          </div>
        </section>
      {/if}
    </main>
  </div>
</div>
