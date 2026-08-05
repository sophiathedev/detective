<script>
  import { onMount } from "svelte"
  import ActionRail from "./game/ActionRail.svelte"
  import CasebookOverlay from "./game/CasebookOverlay.svelte"
  import CasebookWorkspace from "./game/CasebookWorkspace.svelte"
  import ChiselConsole from "./game/ChiselConsole.svelte"
  import ContextStack from "./game/ContextStack.svelte"
  import DetectiveRail from "./game/DetectiveRail.svelte"
  import GameTableShell from "./game/GameTableShell.svelte"
  import MapStage from "./game/MapStage.svelte"
  import PauseCurtain from "./game/PauseCurtain.svelte"

  let { game_id, user_id, initial_public, initial_private } = $props()

  const initialPublic = () => initial_public
  const initialPrivate = () => initial_private

  let publicState = $state(initialPublic())
  let privateState = $state(initialPrivate())
  let connectionState = $state("connecting")
  let drawerOpen = $state(false)
  let drawerPage = $state(initialPrivate().role === "chisel" ? "chisel" : "search")
  let activeAction = $state(null)
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
  let effectiveLegalLocationIds = $derived(
    activeAction === "place"
      ? [...placementLocationIds]
      : activeAction === "move"
        ? [...moveLocationIds]
        : [],
  )
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
  let chiselOnline = $derived(
    Boolean(chisel && connectionSnapshotReceived && onlinePlayerIds.includes(chisel.id)),
  )
  let chiselConnectionLabel = $derived(
    !chisel
      ? "UNASSIGNED"
      : !connectionSnapshotReceived
        ? "SYNCING"
        : chiselOnline
          ? "ONLINE"
          : disconnectCountdown(chisel.id),
  )
  let canResume = $derived(
    privateState.role === "chisel" &&
      allPlayersOnline &&
      availableActions.has("resume_game"),
  )
  let selectedSuspectLeverage = $derived(
    privateState.leverage_on_suspects?.[selectedSuspectId] ?? 0,
  )
  let pauseReason = $derived(
    publicState.pause?.reason ??
      (offlinePlayers.length > 0
        ? `${offlinePlayers.map((player) => player.display_name).join(", ")} disconnected.`
        : "Waiting for every investigator to return."),
  )
  let mapStatus = $derived(
    privateState.role !== "detective"
      ? "Field map · only the active Detective can issue movement commands."
      : mapIntent
      ? `${mapIntent.type === "place" ? "Placing" : "Moving to"} ${locationName(mapIntent.locationId)}…`
      : mapSelection
        ? `${mapSelection.location.name} selected · confirm on the dispatch slip.`
      : activeAction === "place"
        ? "Placement mode · choose one highlighted Police Station."
        : activeAction === "move"
          ? "Move mode · choose one highlighted location in the current district."
          : availableActions.has("place")
            ? "Choose Place below before selecting a Police Station."
            : availableActions.has("move")
              ? "Choose Move below before selecting a destination."
              : "No movement command is currently authorized.",
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
      activeAction = null
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

    const nextActions = new Set(nextState.available_actions ?? [])
    if (activeAction && !nextActions.has(activeAction)) {
      activeAction = null
      mapSelection = null
      mapIntent = null
    }

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

    if (
      activeAction === "place" &&
      placementLocationIds.has(location.id) &&
      availableActions.has("place")
    ) {
      mapSelection = { type: "place", location }
    } else if (
      activeAction === "move" &&
      moveLocationIds.has(location.id) &&
      availableActions.has("move")
    ) {
      mapSelection = { type: "move", location }
    }
  }

  function chooseActionMode(action) {
    if (commandPending || !controlsReady || !availableActions.has(action)) return

    activeAction = activeAction === action ? null : action
    mapSelection = null
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
          activeAction = null
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

  $effect(() => {
    if (drawerPages.some((page) => page.id === drawerPage)) return
    drawerPage = drawerPages[0]?.id ?? "history"
  })

  $effect(() => {
    if (!resynchronizingAfterStale || !controlsReady) return

    resynchronizingAfterStale = false
    commandError = "Game state changed; map resynchronized"
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

  function openCasebook() {
    openDrawer(drawerPages[0]?.id ?? "history")
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
    activeAction = null
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
    activeAction = null
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

<div id="game-book-shell" class="noir-game-book-shell">
  <GameTableShell
    phase={publicState.phase}
    day={publicState.day}
    daysRemaining={publicState.days_remaining}
    activeDetectiveName={activeDetective?.display_name ?? null}
    {connectionState}
    version={publicState.version}
  >
    {#snippet detectiveRail()}
      <DetectiveRail
        players={publicState.players}
        currentDetectiveId={publicState.current_detective_id}
        ownPlayerId={privateState.role === "detective" ? ownPlayer?.id ?? null : null}
        privateResources={privateState.role === "detective"
          ? {
              scratch: privateState.scratch ?? 0,
              leverage: privateState.leverage_supply ?? 0,
            }
          : null}
        {onlinePlayerIds}
        {connectionSnapshotReceived}
        disconnectLabel={disconnectCountdown}
      />
    {/snippet}

    {#snippet chiselConsole()}
      <ChiselConsole
        {chisel}
        isCurrentChisel={privateState.role === "chisel"}
        pendingInterrogation={privateState.role === "chisel" ? pendingPrivate : null}
        leverageByDetective={privateState.role === "chisel"
          ? privateState.leverage_by_detective ?? {}
          : {}}
        detectiveSlots={detectives}
        online={chiselOnline}
        connectionLabel={chiselConnectionLabel}
      />
    {/snippet}

    {#snippet mapStage()}
      <MapStage
        locations={publicState.locations}
        {detectives}
        legalLocationIds={effectiveLegalLocationIds}
        {selectedLocationId}
        pendingLocationId={mapIntent?.locationId ?? null}
        {lastTravel}
        disabled={!controlsReady || commandPending}
        status={mapStatus}
        onSelect={selectMapLocation}
      />
    {/snippet}

    {#snippet contextStack()}
      <ContextStack
        selection={mapSelection}
        origin={ownLocation}
        {commandPending}
        commandError={publicState.status === "paused" ? null : commandError}
        {commandStatus}
        connectionOnline={controlsReady}
        onConfirmMove={confirmMapMovement}
        onCancelMove={cancelMapMovement}
      />
    {/snippet}

    {#snippet actionRail()}
      <ActionRail
        availableActions={[...availableActions]}
        {activeAction}
        {commandPending}
        connectionOnline={controlsReady}
        onChooseAction={chooseActionMode}
        onAction={handleDockAction}
        onOpenCasebook={openCasebook}
      />
    {/snippet}

    {#snippet overlay()}
      <CasebookOverlay
        open={drawerOpen}
        title={drawerTitle}
        page={drawerPage}
        pages={drawerPages}
        onSelectPage={(page) => (drawerPage = page)}
        onClose={closeDrawer}
      >
        {#snippet children()}
          <CasebookWorkspace page={drawerPage} view={casebookView} actions={casebookActions} />
        {/snippet}
      </CasebookOverlay>

      <PauseCurtain
        active={publicState.status === "paused"}
        reason={pauseReason}
        {offlinePlayers}
        {canResume}
        {commandPending}
        commandError={publicState.status === "paused" ? commandError : null}
        onResume={() =>
          retryCommand?.type === "resume_game"
            ? retryLastCommand()
            : sendCommand("resume_game", {})}
      />
    {/snippet}
  </GameTableShell>
</div>

