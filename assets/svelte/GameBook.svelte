<script>
  import { onDestroy, onMount } from "svelte"
  import ActionDock from "./game/ActionDock.svelte"
  import CasebookDrawer from "./game/CasebookDrawer.svelte"
  import CasebookWorkspace from "./game/CasebookWorkspace.svelte"
  import GameBoard from "./game/GameBoard.svelte"
  import PlayerHUD from "./game/PlayerHUD.svelte"

  let { game_id, user_id, initial_public, initial_private } = $props()

  const initialPublic = () => initial_public
  const initialPrivate = () => initial_private

  let publicState = $state(initialPublic())
  let privateState = $state(initialPrivate())
  let connectionState = $state("connecting")
  let drawerOpen = $state(true)
  let drawerPage = $state(initialPrivate().role === "chisel" ? "chisel" : "search")
  let mapSelection = $state(null)
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
  let publicProjectionReady = $state(false)
  let privateProjectionReady = $state(false)
  let publicProjectionVersion = $state(null)
  let privateProjectionVersion = $state(null)
  let resynchronizingAfterStale = $state(false)
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

  const detectiveDrawerPages = [
    { id: "search", label: "Search" },
    { id: "question", label: "Question" },
    { id: "evidence", label: "Evidence" },
    { id: "accusation", label: "Accusation" },
    { id: "history", label: "History" },
  ]
  const chiselDrawerPages = [
    { id: "question", label: "Response" },
    { id: "chisel", label: "Private Case" },
    { id: "history", label: "History" },
  ]

  let detectives = $derived(publicState.players.filter((player) => player.role === "detective"))
  let chisel = $derived(publicState.players.find((player) => player.role === "chisel"))
  let ownPlayer = $derived(publicState.players.find((player) => player.id === privateState.player_id))
  let activeDetective = $derived(
    publicState.players.find((player) => player.id === publicState.current_detective_id),
  )
  let selectedLocationId = $derived(mapSelection?.location.id ?? null)
  let ownLocation = $derived(
    publicState.locations.find((location) => location.id === ownPlayer?.location_id) ?? null,
  )
  let moveLocationIds = $derived(new Set(privateState.valid_move_location_ids ?? []))
  let placementLocationIds = $derived(new Set(privateState.placement_location_ids ?? []))
  let legalLocationIds = $derived([...placementLocationIds, ...moveLocationIds])
  let availableActions = $derived(new Set(privateState.available_actions ?? []))
  let drawerPages = $derived(
    privateState.role === "chisel" ? chiselDrawerPages : detectiveDrawerPages,
  )
  let drawerTitle = $derived(
    drawerPages.find((page) => page.id === drawerPage)?.label ?? "Casebook",
  )
  let projectionsSynchronized = $derived(
    publicProjectionReady &&
      privateProjectionReady &&
      publicProjectionVersion === privateProjectionVersion,
  )
  let controlsReady = $derived(
    connectionState === "online" &&
      projectionsSynchronized &&
      publicState.status !== "paused",
  )
  let commandStatus = $derived(
    commandError?.startsWith("Game state changed;") ?? false,
  )
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
  let mapStatus = $derived(
    privateState.role !== "detective"
      ? "Field map · only the active Detective can issue movement commands."
      : mapIntent
      ? `${mapIntent.type === "place" ? "Placing" : "Moving to"} ${locationName(mapIntent.locationId)}…`
      : mapSelection
        ? `${mapSelection.location.name} selected · confirm on the dispatch slip.`
      : ownPlayer?.location_id
        ? "Select a red-ringed location to review a one-action Move."
        : "Select any available Police Station to review free placement.",
  )
  let casebookView = $derived.by(() => ({
    role: privateState.role,
    phase: publicState.phase,
    result: publicState.result,
    activeDetective,
    ownPlayer,
    availableActions: [...availableActions],
    search: {
      suspects: publicState.suspects.map((suspect) => ({
        ...suspect,
        location_name: locationName(suspect.location_id),
      })),
      selectedSuspectId,
      searchableSuspectIds: [...searchableSuspectIds],
      interrogatableSuspectIds: [...interrogatableSuspectIds],
    },
    question: {
      pendingPublic,
      pendingPrivate: privateState.role === "detective" ? pendingPrivate : null,
      latestStatement,
      interrogationOptions,
      selectedSuspectId,
      selectedTopicId,
      selectedSuspectLeverage,
      spendLeverage,
      selectedResponseId,
      blockedSnitchPlayerIds,
    },
    evidence: { heldEvidence, knownCaseCards, latestSearch },
    accusation: {
      options: accusationOptions,
      selectedSuspectId: accusationSuspectId,
      selectedWeaponId: accusationWeaponId,
      selectedMotiveId: accusationMotiveId,
      solveAttempt: privateState.solve_attempt ?? null,
      finalGuess: privateState.final_guess ?? null,
    },
    history: {
      entries: (publicState.public_history ?? []).map((entry) => ({
        type: entry.type,
        actorName: entry.player_id
          ? publicState.players.find((player) => player.id === entry.player_id)?.display_name ??
            "Detective"
          : "Case file",
      })),
      lastEvent,
      commandError: publicState.status === "paused" ? null : commandError,
      commandStatus,
      retryAvailable: retryCommand !== null,
    },
    chisel:
      privateState.role === "chisel"
        ? {
            identity: chisel,
            pendingInterrogation: pendingPrivate,
            selectedResponseId,
            casebook: privateState.casebook ?? null,
            leverageByDetective: privateState.leverage_by_detective ?? {},
          }
        : null,
  }))

  const casebookActions = {
    selectSuspect,
    selectTopic: (topicId) => (selectedTopicId = topicId),
    setSpendLeverage: (value) => (spendLeverage = value),
    submitSuspectSearch,
    submitInterrogation,
    allowQuestion: () => sendCommand("allow_question", {}),
    blockQuestion: () => sendCommand("block_question", {}),
    acceptQuestionBlock: () => sendCommand("accept_question_block", {}),
    bribeGoon: () => sendCommand("bribe_goon", {}),
    declineSnitch: () => sendCommand("decline_snitch", {}),
    chooseSnitch: () => sendCommand("choose_snitch", {}),
    setBlockedSnitchPlayers: (playerIds) => (blockedSnitchPlayerIds = playerIds),
    submitSnitchResolution,
    selectResponse: (responseId) => (selectedResponseId = responseId),
    submitResponse,
    acceptResponse: () => sendCommand("accept_response", {}),
    challengeResponse: () => sendCommand("challenge_response", {}),
    setAccusationSuspect: (suspectId) => (accusationSuspectId = suspectId),
    setAccusationWeapon: (weaponId) => (accusationWeaponId = weaponId),
    setAccusationMotive: (motiveId) => (accusationMotiveId = motiveId),
    submitAccusation,
    retryCommand: retryLastCommand,
  }

  function applyPublic(nextState) {
    if (nextState.version < publicState.version) return

    const nextOwnPlayer = nextState.players.find(
      (player) => player.id === privateState.player_id,
    )

    if (mapIntent && nextOwnPlayer?.location_id === mapIntent.locationId) {
      mapIntent = null
      mapSelection = null
    }

    publicState = nextState
    publicProjectionVersion = nextState.version
    publicProjectionReady = true
  }

  function applyPrivate(nextState, version) {
    if (version < publicState.version) return
    privateState = nextState
    privateProjectionVersion = version
    privateProjectionReady = true

    if (mapSelection && !mapSelectionLegalIn(mapSelection, nextState)) {
      mapSelection = null
      mapIntent = null
    }
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

  function mapSelectionLegalIn(selection, state) {
    const actions = new Set(state.available_actions ?? [])
    const destinationIds = new Set(
      selection.type === "place"
        ? (state.placement_location_ids ?? [])
        : (state.valid_move_location_ids ?? []),
    )

    return actions.has(selection.type) && destinationIds.has(selection.location.id)
  }

  function selectMapLocation(location) {
    if (commandPending || !controlsReady) return

    if (placementLocationIds.has(location.id) && availableActions.has("place")) {
      mapSelection = { type: "place", location }
    } else if (moveLocationIds.has(location.id) && availableActions.has("move")) {
      mapSelection = { type: "move", location }
    }
  }

  function confirmMapMovement() {
    if (!mapSelection || commandPending || !controlsReady || !gameChannel) return

    mapIntent = {
      type: mapSelection.type,
      locationId: mapSelection.location.id,
    }

    sendCommand(mapSelection.type, { location_id: mapSelection.location.id })
  }

  function cancelMapMovement() {
    if (commandPending) return
    mapSelection = null
  }

  function mapErrorInvalidatesSelection(code) {
    return new Set([
      "destination_outside_district",
      "invalid_location",
      "placement_required",
      "not_your_turn",
      "wrong_phase",
      "wrong_role",
      "no_actions_remaining",
      "game_paused",
    ]).has(code)
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
        if ((type === "place" || type === "move") && mapErrorInvalidatesSelection(code)) {
          mapSelection = null
        }
        commandError = commandErrorMessage(code)
        if (code === "stale_version") requestProjectionResync()
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

  function handleDockAction(action) {
    if (action === "search_suspect") {
      submitSuspectSearch()
    } else if (action === "interrogate") {
      openDrawer("question")
    } else if (action === "accuse" || action === "submit_final_guess") {
      openDrawer("accusation")
    } else {
      sendCommand(action, {})
    }
  }

  function commandErrorMessage(code) {
    const messages = {
      stale_version: "Game state changed; resynchronizing map",
      not_your_turn: "Only the active Detective can act.",
      wrong_role: "This action belongs to a Detective.",
      wrong_phase: "This action is sealed during the current case phase.",
      placement_required: "Place your token at a Police Station first.",
      invalid_location: "That location is not part of the active board catalog.",
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

  $effect(() => {
    if (drawerPages.some((page) => page.id === drawerPage)) return
    drawerPage = drawerPages[0]?.id ?? "history"
  })

  $effect(() => {
    if (!resynchronizingAfterStale || !controlsReady) return

    resynchronizingAfterStale = false
    commandError = "Game state changed; map resynchronized"
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

  function openDrawer(page) {
    drawerPage = page
    drawerOpen = true
  }

  function closeDrawer() {
    drawerOpen = false
  }

  function legalMapLocation(locationId) {
    return placementLocationIds.has(locationId) || moveLocationIds.has(locationId)
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

  function invalidateConnectionSnapshot(nextConnectionState = "offline") {
    connectionState = nextConnectionState
    commandError =
      nextConnectionState === "unauthorized"
        ? "This account is no longer authorized for the case channel."
        : "Connection lost. Waiting for fresh public and private case files."
    connectionSnapshotReceived = false
    onlinePlayerIds = []
    offlineDeadlines = {}
    allPlayersOnline = false
    mapSelection = null
    mapIntent = null
    commandPending = false
    retryCommand = null
    publicProjectionReady = false
    privateProjectionReady = false
    publicProjectionVersion = null
    privateProjectionVersion = null
    resynchronizingAfterStale = false
  }

  function requestProjectionResync() {
    mapSelection = null
    mapIntent = null
    commandPending = false
    retryCommand = null
    publicProjectionReady = false
    privateProjectionReady = false
    publicProjectionVersion = null
    privateProjectionVersion = null
    resynchronizingAfterStale = true

    if (!gameChannel?.isJoined() || !userChannel?.isJoined()) {
      invalidateConnectionSnapshot()
      return
    }

    requestPublicProjectionSync()
    requestPrivateProjectionSync()
  }

  function requestPublicProjectionSync() {
    if (!gameChannel?.isJoined()) return

    gameChannel
      .push("sync_state", {})
      .receive("ok", ({ state }) => applyPublic(state))
      .receive("error", () => invalidateConnectionSnapshot())
      .receive("timeout", () => invalidateConnectionSnapshot())
  }

  function requestPrivateProjectionSync() {
    if (!userChannel?.isJoined()) return

    userChannel
      .push("sync_state", {})
      .receive("ok", ({ state, version }) => applyPrivate(state, version))
      .receive("error", () => invalidateConnectionSnapshot())
      .receive("timeout", () => invalidateConnectionSnapshot())
  }

  function requestMissingProjectionSync() {
    if (!publicProjectionReady) requestPublicProjectionSync()
    if (!privateProjectionReady) requestPrivateProjectionSync()
  }

  onMount(() => {
    const connectionClockInterval = window.setInterval(() => {
      connectionClock = Date.now()
    }, 1000)
    const socket = window.getGameSocket?.()
    if (!socket) {
      invalidateConnectionSnapshot()
      return () => window.clearInterval(connectionClockInterval)
    }

    gameChannel = socket.channel(`game:${game_id}`, {})
    userChannel = socket.channel(`user:${user_id}`, { game_id })

    gameChannel.onError(() => invalidateConnectionSnapshot())
    gameChannel.onClose(() => invalidateConnectionSnapshot())
    userChannel.onError(() => invalidateConnectionSnapshot())
    userChannel.onClose(() => invalidateConnectionSnapshot())

    gameChannel.on("game_state", ({ state }) => applyPublic(state))
    gameChannel.on("connection_state", (state) => {
      onlinePlayerIds = state.online_player_ids
      offlineDeadlines = state.offline_deadlines
      allPlayersOnline = state.all_players_online
      connectionSnapshotReceived = true
      connectionState = "online"
      requestMissingProjectionSync()
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
        requestMissingProjectionSync()
      })
      .receive("error", () => invalidateConnectionSnapshot("unauthorized"))
      .receive("timeout", () => invalidateConnectionSnapshot())

    userChannel
      .join()
      .receive("ok", ({ state, version }) => {
        applyPrivate(state, version)
        requestMissingProjectionSync()
      })
      .receive("error", () => invalidateConnectionSnapshot("unauthorized"))

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

    {#if commandStatus}
      <p id="game-sync-status" class="game-sync-status" role="status" aria-live="polite">{commandError}</p>
    {/if}

    <main
      id="open-casebook"
      class:casebook-drawer-open={drawerOpen}
      class="relative grid min-h-0 flex-1 overflow-hidden border border-[#6f5b45] bg-[#d8c9aa] shadow-[0_24px_70px_rgba(0,0,0,0.55)]"
    >
      <div id="game-casebook-workspace" class="contents" inert={!controlsReady}>
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

          <nav id="casebook-page-tabs" class="casebook-page-tabs" aria-label="Casebook pages">
            {#each drawerPages as page}
              <button
                id={"open-casebook-" + page.id}
                type="button"
                aria-pressed={drawerOpen && drawerPage === page.id}
                onclick={() => openDrawer(page.id)}
                class:casebook-page-tab-active={drawerOpen && drawerPage === page.id}
                class="casebook-page-tab"
              >{page.label}</button>
            {/each}
          </nav>

          <div class="relative min-h-0 flex-1 overflow-hidden bg-[#b7a78b] p-2 sm:p-3">
            <div
              id="map-command-status"
              class={[
                "pointer-events-none absolute left-4 top-4 z-10 max-w-[18rem] border px-3 py-2 font-mono text-[9px] uppercase tracking-[0.1em] shadow-[0_8px_24px_rgba(35,24,16,0.22)] sm:left-5 sm:top-5",
                mapIntent
                  ? "map-command-pending border-[#8e342d] bg-[#f1dec0] text-[#7d2e28]"
                  : "border-[#776149] bg-[#e8dcc3]/95 text-[#5d4b38]",
              ]}
              aria-live="polite"
              aria-busy={mapIntent !== null}
            >
              {mapStatus}
            </div>
            <GameBoard
              locations={publicState.locations}
              {detectives}
              {legalLocationIds}
              {selectedLocationId}
              pendingLocationId={mapIntent?.locationId ?? null}
              {lastTravel}
              disabled={commandPending || !controlsReady}
              onSelect={selectMapLocation}
            />
            <p class="mt-2 font-mono text-[8px] leading-3 text-[#594936] sm:text-[9px]">
              Board artwork © Van Ryder Games / Vincent Dutrait. Unofficial non-commercial fan project; not affiliated with or endorsed by the publisher.
            </p>
          </div>
        </section>

        <CasebookDrawer open={drawerOpen} title={drawerTitle} onClose={closeDrawer}>
          <section class="relative flex min-h-0 flex-col bg-[#e4d8bd]">
            <PlayerHUD
              players={publicState.players}
              currentDetectiveId={publicState.current_detective_id}
              {privateState}
              {onlinePlayerIds}
              {connectionSnapshotReceived}
              disconnectLabel={disconnectCountdown}
            />

            <div class="min-h-0 flex-1 overflow-auto p-4 sm:p-5">
              {#if drawerPage === "search"}
                <ActionDock
                  {availableActions}
                  selection={mapSelection}
                  origin={ownLocation}
                  {commandPending}
                  commandError={commandStatus ? null : commandError}
                  commandStatus={false}
                  connectionOnline={controlsReady}
                  onConfirmMove={confirmMapMovement}
                  onCancelMove={cancelMapMovement}
                  onAction={handleDockAction}
                />
              {/if}

              <CasebookWorkspace page={drawerPage} view={casebookView} actions={casebookActions} />

              {#if drawerPage === "search"}
                <section id="keyboard-location-list" class="mt-5 border-t border-[#a38b6e] pt-4" aria-labelledby="location-list-heading">
                  <h3 id="location-list-heading" class="font-mono text-[10px] uppercase tracking-[0.14em] text-[#80694f]">Location index</h3>
                  <div class="mt-2 grid gap-1 sm:grid-cols-2">
                    {#each publicState.locations as location}
                      {#if legalMapLocation(location.id)}
                        <button
                          id={"location-index-" + location.id}
                          type="button"
                          onclick={() => selectMapLocation(location)}
                          class="min-h-11 cursor-pointer bg-[#a54235] px-2 py-1.5 text-left text-xs text-[#fff0d6] transition hover:bg-[#b94d3f]"
                        >
                          {location.name}
                          <span class="float-right font-mono text-[9px] uppercase">legal</span>
                        </button>
                      {:else}
                        <div id={"location-index-" + location.id} class="px-2 py-1.5 text-left text-xs text-[#6f5c47]">
                          {location.name}
                          <span class="float-right font-mono text-[9px] uppercase">{location.type.replaceAll("_", " ")}</span>
                        </div>
                      {/if}
                    {/each}
                  </div>
                </section>
              {/if}
            </div>
          </section>
        </CasebookDrawer>
      </div>

      {#if publicState.status === "paused"}
        <section
          id="game-pause-seal"
          class="game-pause-seal"
          role="status"
          aria-labelledby="game-pause-heading"
          aria-describedby="game-pause-description"
        >
          <div id="game-pause-document" class="game-pause-document" role="document" tabindex="-1" bind:this={pauseDocument}>
            <p class="game-pause-kicker">Case sealed</p>
            <h2 id="game-pause-heading" class="mt-2 font-serif text-3xl font-semibold tracking-[-0.025em] sm:text-4xl">Investigation paused</h2>
            <p id="game-pause-description" class="mt-3 font-serif text-base italic leading-7">Waiting for every investigator to return.</p>

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
                  <button id="action-retry-resume-game" type="button" onclick={retryLastCommand}>Retry resume</button>
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

