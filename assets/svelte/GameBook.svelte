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
  import { buildImmediateActionPrompt } from "./game/actionPrompts"
  import { caseCardCodeFromPrivateEvent } from "./game/caseCardFocus"
  import { directMapLocationIds, directMapMovementType } from "./game/mapMovement"
  import { initializeI18n } from "./i18n"

  let {
    game_id,
    user_id,
    initial_public,
    initial_private,
    csrf_token = "",
    locale = "en",
    return_path = `/games/${game_id}`,
  } = $props()
  const { t } = initializeI18n(() => locale)

  const initialPublic = () => initial_public
  const initialPrivate = () => initial_private

  let publicState = $state(initialPublic())
  let privateState = $state(initialPrivate())
  let connectionState = $state("connecting")
  let drawerOpen = $state(false)
  let drawerPage = $state(initialPrivate().role === "chisel" ? "chisel" : "search")
  let activeAction = $state(null)
  let mapSelection = $state(null)
  let mapFieldSelectionPlayerId = $state(null)
  let mapSuspectSelectionId = $state(null)
  let mapSpecialActorSelectionId = $state(null)
  let actionPrompt = $state(null)
  let selectedSuspectId = $state(null)
  let selectedTopicId = $state(null)
  let selectedResponseId = $state(null)
  let blockedSnitchPlayerIds = $state([])
  let accusationSuspectId = $state(null)
  let accusationWeaponId = $state(null)
  let accusationMotiveId = $state(null)
  let selectedEvidenceCaseCardCode = $state(null)
  let bribeMode = $state("detective")
  let selectedBribeTargetId = $state(null)
  let selectedBribeCardId = $state(null)
  let spendLeverage = $state(false)
  let commandPending = $state(false)
  let retryCommand = $state(null)
  let commandError = $state(null)
  let publicProjectionReady = $state(false)
  let privateProjectionReady = $state(false)
  let publicProjectionVersion = $state(null)
  let privateProjectionVersion = $state(null)
  let resynchronizingAfterStale = $state(false)
  let lastEvent = $state(t("Casebook synchronized."))
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
    { id: "search", label: t("Search") },
    { id: "question", label: t("Question") },
    { id: "evidence", label: t("Evidence") },
    { id: "bribes", label: t("Bribes") },
    { id: "accusation", label: t("Accusation") },
    { id: "history", label: t("History") },
  ]
  const chiselDrawerPages = [
    { id: "question", label: t("Response") },
    { id: "chisel", label: t("Private case") },
    { id: "history", label: t("History") },
  ]
  const fieldActionTypes = ["search_location", "analyze", "kickback", "bribe_officer"]

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
  let availableActions = $derived(new Set(privateState.available_actions ?? []))
  let mapMovementType = $derived(directMapMovementType(activeAction, availableActions))
  let effectiveLegalLocationIds = $derived(
    directMapLocationIds(mapMovementType, placementLocationIds, moveLocationIds),
  )
  let availableFieldActionTypes = $derived(
    fieldActionTypes.filter((action) => availableActions.has(action)),
  )
  let drawerPages = $derived(
    privateState.role === "chisel" ? chiselDrawerPages : detectiveDrawerPages,
  )
  let drawerTitle = $derived(
    drawerPages.find((page) => page.id === drawerPage)?.label ?? t("Casebook"),
  )
  let drawerFolioLabel = $derived(
    privateState.role === "chisel" ? t("Chisel private casebook") : t("Detective field folio"),
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
  let specialActorInteractions = $derived(privateState.special_actor_interactions ?? [])
  let interactableSpecialActorIds = $derived(
    new Set(specialActorInteractions.map((interaction) => interaction.actor_id)),
  )
  let mapSuspectSelection = $derived.by(() => {
    if (!mapSuspectSelectionId) return null

    const suspect = publicState.suspects.find(
      (candidate) => candidate.id === mapSuspectSelectionId,
    )
    const location = publicState.locations.find(
      (candidate) => candidate.id === suspect?.location_id,
    )
    const canSearch =
      availableActions.has("search_suspect") && searchableSuspectIds.has(mapSuspectSelectionId)
    const canInterrogate =
      availableActions.has("interrogate") && interrogatableSuspectIds.has(mapSuspectSelectionId)

    return suspect && location && (canSearch || canInterrogate)
      ? { suspect, location, canSearch, canInterrogate }
      : null
  })
  let mapFieldSelection = $derived.by(() => {
    if (
      mapFieldSelectionPlayerId !== ownPlayer?.id ||
      !ownLocation ||
      availableFieldActionTypes.length === 0
    )
      return null

    return {
      detective: ownPlayer,
      location: ownLocation,
      actionTypes: availableFieldActionTypes,
    }
  })
  let mapSpecialActorSelection = $derived.by(() => {
    if (!mapSpecialActorSelectionId) return null

    const actor = (publicState.special_actors ?? []).find(
      (candidate) => candidate.id === mapSpecialActorSelectionId,
    )
    const interaction = specialActorInteractions.find(
      (candidate) => candidate.actor_id === mapSpecialActorSelectionId,
    )
    const location = publicState.locations.find(
      (candidate) => candidate.id === actor?.location_id,
    )

    return actor && actor.active && interaction?.options?.length > 0 && location
      ? { actor, location, options: interaction.options }
      : null
  })
  let selectedInterrogation = $derived(
    interrogationOptions.find((option) => option.suspect_id === selectedSuspectId),
  )
  let selectedTopic = $derived(
    selectedInterrogation?.topics.find((topic) => topic.id === selectedTopicId),
  )
  let pendingPublic = $derived(publicState.pending_interrogation)
  let pendingPrivate = $derived(privateState.pending_interrogation)
  let latestStatement = $derived(privateState.statements?.[0])
  let heldEvidence = $derived(privateState.evidence ?? [])
  let knownCaseCards = $derived(privateState.known_case_cards ?? [])
  let accessibleCaseCards = $derived.by(() => {
    const cardsByCode = new Map()

    for (const card of publicState.case_cards ?? []) {
      cardsByCode.set(card.code, { ...card, visibility: "public" })
    }
    for (const card of knownCaseCards) {
      if (!cardsByCode.has(card.code)) {
        cardsByCode.set(card.code, { ...card, visibility: "known" })
      }
    }
    for (const card of heldEvidence) {
      cardsByCode.set(card.code, {
        ...(cardsByCode.get(card.code) ?? {}),
        ...card,
        visibility: "held",
      })
    }

    return (publicState.case_card_slots ?? [])
      .map((slot) => cardsByCode.get(slot.code))
      .filter(Boolean)
  })
  let inspectableCaseCardCodes = $derived(
    privateState.role === "detective" ? accessibleCaseCards.map((card) => card.code) : [],
  )
  let accusationOptions = $derived(
    privateState.accusation_options ?? { suspects: [], weapons: [], motives: [] },
  )
  let bribeOptions = $derived(
    privateState.bribe_options ?? { detective_targets: [], officer_case_cards: [] },
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
        ? t("{names} disconnected.", { names: offlinePlayers.map((player) => player.display_name).join(", ") })
        : t("Waiting for every investigator to return.")),
  )
  let mapStatus = $derived(
    privateState.role !== "detective"
      ? t("Field map · only the active Detective can dispatch a car.")
      : mapIntent
      ? mapIntent.type === "place"
        ? t("Starting from {location}…", { location: locationName(mapIntent.locationId) })
        : t("Driving to {location}…", { location: locationName(mapIntent.locationId) })
      : mapSelection
        ? t("{location} selected · confirm on the dispatch slip.", { location: mapSelection.location.name })
        : mapSpecialActorSelection
          ? t("{actor} selected · choose a case-specific interaction.", { actor: mapSpecialActorSelection.actor.name })
          : mapMovementType === "place"
            ? t("Choose a highlighted precinct as your starting point.")
            : mapMovementType === "move"
              ? t("Click a highlighted destination to move within the current district.")
              : t("No movement order is currently authorized."),
  )
  let casebookView = $derived.by(() => ({
    role: privateState.role,
    phase: publicState.phase,
    result: publicState.result,
    specialRules: publicState.special_rules ?? [],
    detectives,
    activeDetective,
    ownPlayer,
    availableActions: [...availableActions],
    search: {
      currentLocation: ownLocation,
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
      freeQuestionSuspectId: privateState.free_question_suspect_id ?? null,
      selectedSuspectLeverage,
      spendLeverage,
      selectedResponseId,
      blockedSnitchPlayerIds,
    },
    evidence: {
      heldEvidence,
      knownCaseCards,
      caseCards: accessibleCaseCards,
      selectedCaseCardCode: selectedEvidenceCaseCardCode,
      searchNotes: privateState.search_notes ?? [],
    },
    bribes: {
      mode: bribeMode,
      scratch: privateState.scratch ?? 0,
      options: bribeOptions,
      selectedTargetId: selectedBribeTargetId,
      selectedCardId: selectedBribeCardId,
    },
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
    submitLocationSearch: () => sendCommand("search_location", {}),
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
    setBribeMode: prepareBribeSelection,
    setBribeTarget: selectBribeTarget,
    setBribeCard: (cardId) => (selectedBribeCardId = cardId),
    submitBribe,
    setAccusationSuspect: (suspectId) => (accusationSuspectId = suspectId),
    setAccusationWeapon: (weaponId) => (accusationWeaponId = weaponId),
    setAccusationMotive: (motiveId) => (accusationMotiveId = motiveId),
    selectEvidenceCaseCard,
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
      mapFieldSelectionPlayerId = null
      activeAction = null
    }

    if (
      mapSuspectSelectionId &&
      !(nextState.suspects ?? []).some((suspect) => suspect.id === mapSuspectSelectionId)
    ) {
      mapSuspectSelectionId = null
    }

    if (
      mapSpecialActorSelectionId &&
      !(nextState.special_actors ?? []).some(
        (actor) => actor.id === mapSpecialActorSelectionId && actor.active,
      )
    ) {
      mapSpecialActorSelectionId = null
    }

    if (
      mapFieldSelectionPlayerId &&
      !(nextState.players ?? []).some(
        (player) => player.id === mapFieldSelectionPlayerId && player.location_id,
      )
    ) {
      mapFieldSelectionPlayerId = null
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

    if (mapSuspectSelectionId && !mapSuspectSelectableIn(mapSuspectSelectionId, nextState)) {
      mapSuspectSelectionId = null
    }

    if (
      mapSpecialActorSelectionId &&
      !mapSpecialActorSelectableIn(mapSpecialActorSelectionId, nextState)
    ) {
      mapSpecialActorSelectionId = null
    }

    if (mapFieldSelectionPlayerId && fieldActionTypesIn(nextState).length === 0) {
      mapFieldSelectionPlayerId = null
    }

    if (actionPrompt && !nextActions.has(actionPrompt.type)) {
      actionPrompt = null
    }

    if (nextState.role === "detective" && nextState.free_question_suspect_id) {
      prepareQuestionSelection(
        nextState.interrogation_options ?? [],
        nextState.free_question_suspect_id,
      )
    }

    if (nextState.role === "detective") {
      synchronizeBribeSelection(nextState.bribe_options ?? bribeOptions)
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

    lastEvent = t(description)
    return true
  }

  function recordQuestionEvent(message, description) {
    if (!recordPublicEvent(message, description)) return false

    openDrawer("question")
    return true
  }

  function recordAccusationEvent(message, description) {
    if (!recordPublicEvent(message, description)) return false

    openDrawer("accusation")
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

  function mapSuspectSelectableIn(suspectId, state) {
    const actions = new Set(state.available_actions ?? [])
    const searchable = new Set(state.searchable_suspect_ids ?? [])
    const interrogatable = new Set(
      (state.interrogation_options ?? []).map((option) => option.suspect_id),
    )

    return (
      (actions.has("search_suspect") && searchable.has(suspectId)) ||
      (actions.has("interrogate") && interrogatable.has(suspectId))
    )
  }

  function mapSpecialActorSelectableIn(actorId, state) {
    const actions = new Set(state.available_actions ?? [])
    const interactions = state.special_actor_interactions ?? []

    return (
      actions.has("interact_special_actor") &&
      interactions.some(
        (interaction) => interaction.actor_id === actorId && interaction.options?.length > 0,
      )
    )
  }

  function fieldActionTypesIn(state) {
    const actions = new Set(state.available_actions ?? [])
    return fieldActionTypes.filter((action) => actions.has(action))
  }

  function selectMapLocation(location) {
    if (commandPending || !controlsReady) return

    if (
      mapMovementType === "place" &&
      placementLocationIds.has(location.id) &&
      availableActions.has("place")
    ) {
      mapSelection = { type: "place", location }
      mapFieldSelectionPlayerId = null
      mapSuspectSelectionId = null
      mapSpecialActorSelectionId = null
    } else if (
      mapMovementType === "move" &&
      moveLocationIds.has(location.id) &&
      availableActions.has("move")
    ) {
      mapSelection = { type: "move", location }
      mapFieldSelectionPlayerId = null
      mapSuspectSelectionId = null
      mapSpecialActorSelectionId = null
    }
  }

  function selectMapSuspect(suspect) {
    if (commandPending || !controlsReady || activeAction) return
    if (!mapSuspectSelectableIn(suspect.id, privateState)) return

    selectSuspect(suspect.id)
    mapSuspectSelectionId = suspect.id
    mapFieldSelectionPlayerId = null
    mapSpecialActorSelectionId = null
    mapSelection = null
    actionPrompt = null
  }

  function openMapSuspectAction(selection, action) {
    if (
      !selection ||
      selection.suspect.id !== mapSuspectSelectionId ||
      commandPending ||
      !controlsReady
    )
      return

    const allowed =
      (action === "search_suspect" && selection.canSearch) ||
      (action === "interrogate" && selection.canInterrogate)
    if (!allowed) return

    selectSuspect(selection.suspect.id)
    mapSuspectSelectionId = null
    openDrawer(action === "search_suspect" ? "search" : "question")
  }

  function cancelMapSuspect() {
    if (commandPending) return
    mapSuspectSelectionId = null
  }

  function selectMapSpecialActor(actor) {
    if (commandPending || !controlsReady || activeAction) return
    if (!mapSpecialActorSelectableIn(actor.id, privateState)) return

    mapSpecialActorSelectionId = actor.id
    mapSuspectSelectionId = null
    mapFieldSelectionPlayerId = null
    mapSelection = null
    actionPrompt = null
  }

  function interactWithSpecialActor(selection, option) {
    if (
      !selection ||
      selection.actor.id !== mapSpecialActorSelectionId ||
      !selection.options.some((candidate) => candidate.id === option.id) ||
      commandPending ||
      !controlsReady
    )
      return

    mapSpecialActorSelectionId = null
    sendCommand("interact_special_actor", {
      actor_id: selection.actor.id,
      option_id: option.id,
    })
  }

  function cancelMapSpecialActor() {
    if (commandPending) return
    mapSpecialActorSelectionId = null
  }

  function selectMapDetective(detective) {
    if (commandPending || !controlsReady || activeAction) return
    if (detective.id !== ownPlayer?.id || fieldActionTypesIn(privateState).length === 0) return

    mapFieldSelectionPlayerId = detective.id
    mapSuspectSelectionId = null
    mapSpecialActorSelectionId = null
    mapSelection = null
    actionPrompt = null
  }

  function selectBoardCaseCard(slot) {
    if (privateState.role !== "detective" || !inspectableCaseCardCodes.includes(slot.code)) return

    selectedEvidenceCaseCardCode = slot.code
    openDrawer("evidence")
  }

  function selectEvidenceCaseCard(code) {
    if (privateState.role !== "detective" || !inspectableCaseCardCodes.includes(code)) return

    selectedEvidenceCaseCardCode = code
  }

  function openMapFieldAction(selection, action) {
    if (
      !selection ||
      selection.detective.id !== mapFieldSelectionPlayerId ||
      commandPending ||
      !controlsReady ||
      !fieldActionTypesIn(privateState).includes(action)
    )
      return

    mapFieldSelectionPlayerId = null
    handleDockAction(action)
  }

  function cancelMapField() {
    if (commandPending) return
    mapFieldSelectionPlayerId = null
  }

  function chooseActionMode(action) {
    if (commandPending || !controlsReady || !availableActions.has(action)) return

    activeAction = activeAction === action ? null : action
    mapSelection = null
    mapFieldSelectionPlayerId = null
    mapSuspectSelectionId = null
    mapSpecialActorSelectionId = null
    actionPrompt = null
  }

  function confirmMapMovement() {
    if (!mapSelection || commandPending || !controlsReady || !gameChannel) return

    mapIntent = {
      type: mapSelection.type,
      locationId: mapSelection.location.id,
    }

    sendCommand(mapSelection.type, { location_id: mapSelection.location.id })
  }

  function cancelMapMovement(selection) {
    if (commandPending) return
    mapSelection = null
    if (selection?.type === activeAction) activeAction = null
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
          commandError = t("Command unconfirmed. Retry uses the same command ID.")
      })
  }

  function retryLastCommand() {
    if (retryCommand) sendCommand(retryCommand.type, retryCommand.payload, retryCommand)
  }

  function immediateActionPrompt(action) {
    return buildImmediateActionPrompt(action, {
      actionsRemaining: ownPlayer?.actions_remaining ?? 0,
      playerCount: publicState.players.length,
      t,
    })
  }

  function confirmImmediateAction(prompt) {
    if (!prompt || prompt.type !== actionPrompt?.type) return

    actionPrompt = null
    sendCommand(prompt.type, {})
  }

  function cancelImmediateAction() {
    if (commandPending) return
    actionPrompt = null
  }

  function handleDockAction(action) {
    const prompt = immediateActionPrompt(action)
    mapFieldSelectionPlayerId = null
    mapSuspectSelectionId = null
    mapSpecialActorSelectionId = null

    if (action === "search_location" || action === "search_suspect") {
      openDrawer("search")
    } else if (action === "interrogate") {
      prepareQuestionSelection()
      openDrawer("question")
    } else if (action === "accuse" || action === "submit_final_guess") {
      openDrawer("accusation")
    } else if (action === "bribe_detective" || action === "bribe_officer") {
      prepareBribeSelection(action === "bribe_officer" ? "officer" : "detective")
      openDrawer("bribes")
    } else if (prompt && availableActions.has(action)) {
      activeAction = null
      mapSelection = null
      actionPrompt = prompt
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
      placement_required: "Choose a starting Police Station first.",
      invalid_location: "That location is not part of the active board catalog.",
      police_station_required: "Bribe Officer is available only at a Police Station.",
      destination_outside_district: "That location is outside the current district.",
      no_actions_remaining: "No actions remain this turn.",
      mob_joint_required: "Kickback is available only at a Mob Joint.",
      kickback_already_used: "Kickback was already used today.",
      invalid_bribe_target: "That Detective cannot receive this bribe.",
      bribe_target_not_at_location: "Move to the same location as that Detective first.",
      case_card_not_known_by_target: "That Detective does not hold the selected knowledge marker.",
      case_card_not_known_by_detective: "No other Detective knows that Case card.",
      case_card_already_known: "You already know that Case card.",
      invalid_case_card: "That Case card is not part of the active case.",
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
      invalid_special_interaction: "That case-specific interaction is not available.",
      special_actor_not_at_location: "Move to the special contact's location first.",
      special_interaction_used: "That case-specific interaction has already been resolved.",
      special_choice_resolved: "Another approach to that contact has already been filed.",
      special_actor_blocks_action: "Counter-surveillance is blocking that action at this location.",
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
      rate_limited: "Dispatch rejected a burst of orders. Wait a moment before transmitting again.",
    }

    return t(messages[code] ?? "The server rejected this action.")
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
    commandError = t("Game state changed; map resynchronized")
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

  function prepareQuestionSelection(options = interrogationOptions, preferredSuspectId = null) {
    const current = options.find((option) => option.suspect_id === selectedSuspectId)
    const preferred = options.find((option) => option.suspect_id === preferredSuspectId)
    const interrogation = preferred ?? current ?? options[0]

    if (!interrogation) {
      selectedSuspectId = null
      selectedTopicId = null
      spendLeverage = false
      return
    }

    const suspectChanged = selectedSuspectId !== interrogation.suspect_id
    selectedSuspectId = interrogation.suspect_id

    if (
      suspectChanged ||
      !(interrogation.topics ?? []).some((topic) => topic.id === selectedTopicId)
    ) {
      selectedTopicId = interrogation.topics[0]?.id ?? null
    }

    if (suspectChanged) spendLeverage = false
  }

  function prepareBribeSelection(mode) {
    bribeMode = mode === "officer" ? "officer" : "detective"
    selectedBribeTargetId = null
    selectedBribeCardId = null
    synchronizeBribeSelection(bribeOptions)
  }

  function synchronizeBribeSelection(options) {
    if (bribeMode === "officer") {
      selectedBribeTargetId = null
      const officerCards = options.officer_case_cards ?? []
      const selected = officerCards.find((card) => card.id === selectedBribeCardId)
      selectedBribeCardId = selected?.id ?? officerCards[0]?.id ?? null
      return
    }

    const targets = options.detective_targets ?? []
    const target =
      targets.find((detective) => detective.player_id === selectedBribeTargetId) ?? targets[0]

    selectedBribeTargetId = target?.player_id ?? null
    const cards = target?.case_cards ?? []
    const selected = cards.find((card) => card.id === selectedBribeCardId)
    selectedBribeCardId = selected?.id ?? cards[0]?.id ?? null
  }

  function selectBribeTarget(playerId) {
    const target = bribeOptions.detective_targets?.find(
      (detective) => detective.player_id === playerId,
    )

    selectedBribeTargetId = target?.player_id ?? null
    selectedBribeCardId = target?.case_cards?.[0]?.id ?? null
  }

  function openDrawer(page) {
    actionPrompt = null
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

  function submitBribe() {
    if (!selectedBribeCardId) return

    if (bribeMode === "officer") {
      if (!availableActions.has("bribe_officer")) return
      sendCommand("bribe_officer", { case_card_id: selectedBribeCardId })
      return
    }

    if (!availableActions.has("bribe_detective") || !selectedBribeTargetId) return

    sendCommand("bribe_detective", {
      detective_player_id: selectedBribeTargetId,
      case_card_id: selectedBribeCardId,
    })
  }

  function invalidateConnectionSnapshot(nextConnectionState = "offline") {
    connectionState = nextConnectionState
    commandError =
      nextConnectionState === "unauthorized"
        ? t("This account is no longer authorized for the case channel.")
        : t("Connection lost. Waiting for fresh public and private case files.")
    connectionSnapshotReceived = false
    onlinePlayerIds = []
    offlineDeadlines = {}
    allPlayersOnline = false
    mapSelection = null
    mapFieldSelectionPlayerId = null
    mapSuspectSelectionId = null
    mapSpecialActorSelectionId = null
    mapIntent = null
    activeAction = null
    actionPrompt = null
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
    mapFieldSelectionPlayerId = null
    mapSuspectSelectionId = null
    mapSpecialActorSelectionId = null
    mapIntent = null
    activeAction = null
    actionPrompt = null
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
    userChannel = socket.channel(`user:${user_id}:game:${game_id}`, { game_id })

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
    gameChannel.on("special_actor_interacted", (message) => {
      const payload = message.payload ?? {}
      const contactMoved =
        payload.actor_from_location_id &&
        payload.actor_location_id &&
        payload.actor_from_location_id !== payload.actor_location_id
      const openedLead =
        payload.revealed_case_card_codes?.length > 0 || payload.revealed_suspect_ids?.length > 0

      const summary = contactMoved
        ? openedLead
          ? "A contact relocated and opened a public lead."
          : "A case-specific contact relocated."
        : openedLead
          ? "A case-specific contact opened a public lead."
          : "A case-specific contact changed the investigation."

      recordPublicEvent(message, summary)
    })
    gameChannel.on("evidence_submitted", (message) =>
      recordPublicEvent(message, "Held evidence returned to the public casefile."),
    )
    gameChannel.on("free_question_declined", (message) =>
      recordPublicEvent(message, "The immediate question was declined."),
    )
    gameChannel.on("question_allowed", (message) =>
      recordQuestionEvent(message, "The Chisel allowed the question to proceed."),
    )
    gameChannel.on("question_blocked", (message) =>
      recordQuestionEvent(message, "The Chisel sent a goon to block the question."),
    )
    gameChannel.on("question_abandoned", (message) =>
      recordPublicEvent(message, "The blocked question was abandoned."),
    )
    gameChannel.on("goon_bribed", (message) =>
      recordQuestionEvent(message, "The Detective paid the goon and restored the question."),
    )
    gameChannel.on("detective_bribed", (message) =>
      recordPublicEvent(
        message,
        t("A Detective bought access to Case {code}.", { code: message.payload.case_card_code }),
      ),
    )
    gameChannel.on("officer_bribed", (message) =>
      recordPublicEvent(
        message,
        t("A desk officer opened Case {code}.", { code: message.payload.case_card_code }),
      ),
    )
    gameChannel.on("snitch_decision_recorded", (message) =>
      recordPublicEvent(message, "A facedown Snitch decision was filed."),
    )
    gameChannel.on("snitch_window_closed", (message) =>
      recordQuestionEvent(message, "All Snitch decisions were revealed."),
    )
    gameChannel.on("snitches_resolved", (message) =>
      recordQuestionEvent(message, "The Chisel resolved the revealed Snitch requests."),
    )
    gameChannel.on(
      "interrogation_started",
      (message) => {
        selectedResponseId = null
        blockedSnitchPlayerIds = []
        recordQuestionEvent(message, "A suspect was called in for questioning.")
      },
    )
    gameChannel.on(
      "response_published",
      (message) =>
        recordQuestionEvent(message, "The suspect's statement was delivered under seal."),
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
    gameChannel.on("special_rule_triggered", (message) => {
      const actorChanged = message.payload.special_actor_updates?.length > 0
      recordPublicEvent(
        message,
        actorChanged
          ? "A case-specific figure entered or changed position on the map."
          : "A case-specific rule changed the investigation.",
      )
    })
    gameChannel.on("accusation_opened", (message) =>
      recordAccusationEvent(message, "Time expired. The accusation phase is open."),
    )
    gameChannel.on("accusation_submitted", (message) =>
      recordAccusationEvent(message, "A Detective submitted a Solve accusation."),
    )
    gameChannel.on("accusation_rejected", (message) =>
      recordAccusationEvent(message, "A Solve accusation was incorrect."),
    )
    gameChannel.on("final_guess_submitted", (message) =>
      recordAccusationEvent(message, "A sealed final guess entered the casefile."),
    )
    gameChannel.on("game_finished", (message) =>
      recordAccusationEvent(message, "The case is closed and the solution is public."),
    )

    userChannel.on("private_state", ({ game_id: eventGameId, state, version }) => {
      if (eventGameId === game_id) applyPrivate(state, version)
    })

    userChannel.on("private_event", (message) => {
      const { game_id: eventGameId, payload } = message
      if (eventGameId !== game_id) return
      if (!acceptEvent(message, seenPrivateEventIds)) return

      const eventCaseCardCode = caseCardCodeFromPrivateEvent(payload)
      if (eventCaseCardCode) selectedEvidenceCaseCardCode = eventCaseCardCode

      if (payload.type === "challenge_resolved") {
        lastEvent = payload.succeeded
          ? "Challenge sustained. The corrected statement is now in your notes."
          : "Challenge failed. The original statement was truthful."
      } else if (payload.type === "search_result") {
        lastEvent = payload.free_question_suspect_id
          ? "Search complete. A newly discovered suspect may be questioned for free."
          : "Search complete. The private result is filed in your notebook."
        openDrawer(payload.free_question_suspect_id ? "question" : "evidence")
      } else if (payload.type === "bribe_result") {
        lastEvent = t("Case {code} entered your private evidence folio.", { code: payload.case_card.code })
        openDrawer("evidence")
      } else if (payload.type === "special_actor_result") {
        lastEvent =
          payload.case_cards?.length > 0
            ? "The special interaction added private evidence to your casebook."
            : "The special interaction was resolved."
        if (payload.case_cards?.length > 0) openDrawer("evidence")
      } else if (payload.type === "scratch_updated" && payload.received) {
        lastEvent = t("You received ${amount} Scratch from another Detective.", { amount: payload.received })
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
          : t("{count} of 3 accusation elements were correct.", { count: payload.correct_count })
        openDrawer("accusation")
      } else if (payload.type === "final_guess_recorded") {
        lastEvent = "Your final guess is sealed until every Detective submits."
        openDrawer("accusation")
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
    returnPath={return_path}
    csrfToken={csrf_token}
  >
    {#snippet detectiveRail()}
      <DetectiveRail
        players={publicState.players}
        locations={publicState.locations}
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
        actionableDetectiveId={availableFieldActionTypes.length > 0 ? ownPlayer?.id ?? null : null}
        detectiveActionTypes={availableFieldActionTypes}
        selectedDetectiveId={mapFieldSelectionPlayerId}
        detectiveInteractionsDisabled={activeAction !== null}
        suspects={publicState.suspects ?? []}
        searchableSuspectIds={[...searchableSuspectIds]}
        interrogatableSuspectIds={[...interrogatableSuspectIds]}
        selectedSuspectId={mapSuspectSelectionId}
        suspectInteractionsDisabled={activeAction !== null}
        specialActors={publicState.special_actors ?? []}
        interactableSpecialActorIds={[...interactableSpecialActorIds]}
        selectedSpecialActorId={mapSpecialActorSelectionId}
        specialActorInteractionsDisabled={activeAction !== null}
        caseCardSlots={publicState.case_card_slots ?? []}
        {inspectableCaseCardCodes}
        selectedCaseCardCode={drawerOpen && drawerPage === "evidence"
          ? selectedEvidenceCaseCardCode
          : null}
        legalLocationIds={effectiveLegalLocationIds}
        {selectedLocationId}
        pendingLocationId={mapIntent?.locationId ?? null}
        {lastTravel}
        disabled={!controlsReady || commandPending}
        status={mapStatus}
        onSelect={selectMapLocation}
        onSelectDetective={selectMapDetective}
        onSelectSuspect={selectMapSuspect}
        onSelectSpecialActor={selectMapSpecialActor}
        onSelectCaseCard={selectBoardCaseCard}
      />
    {/snippet}

    {#snippet contextStack()}
      <ContextStack
        selection={mapSelection}
        fieldSelection={mapFieldSelection}
        suspectSelection={mapSuspectSelection}
        specialActorSelection={mapSpecialActorSelection}
        {actionPrompt}
        origin={ownLocation}
        {commandPending}
        commandError={publicState.status === "paused" ? null : commandError}
        {commandStatus}
        connectionOnline={controlsReady}
        onConfirmMove={confirmMapMovement}
        onCancelMove={cancelMapMovement}
        onOpenFieldAction={openMapFieldAction}
        onCancelField={cancelMapField}
        onOpenSuspectAction={openMapSuspectAction}
        onCancelSuspect={cancelMapSuspect}
        onInteractSpecialActor={interactWithSpecialActor}
        onCancelSpecialActor={cancelMapSpecialActor}
        onConfirmAction={confirmImmediateAction}
        onCancelAction={cancelImmediateAction}
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
        folioLabel={drawerFolioLabel}
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
