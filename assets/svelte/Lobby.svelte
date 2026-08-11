<script>
  import { onMount } from "svelte"

  import PortraitToken from "./ui/PortraitToken.svelte"
  import StatusStamp from "./ui/StatusStamp.svelte"
  import { initializeI18n } from "./i18n"

  let { lobby, case_options = [], locale = "en" } = $props()
  const { t } = initializeI18n(() => locale)

  const initialLobby = () => lobby

  let room = $state(initialLobby())
  let onlinePlayerIds = $state(new Set())
  let presenceState = $state({})
  let channel = null
  let connectionState = $state("connecting")
  let commandPending = $state(false)
  let commandError = $state(null)
  let startCommandId = null
  let pendingRemovalId = $state(null)
  let leaveArmed = $state(false)
  let cancelArmed = $state(false)
  let revokeArmed = $state(false)
  let inviteHours = $state(24)
  let inviteUrl = $state(null)
  let inviteCopied = $state(false)
  let settingsOpen = $state(false)
  let settingsCaseVersionId = $state(null)
  let settingsMaxDetectives = $state(null)

  let detectives = $derived(room.players.filter((player) => player.role === "detective"))
  let detectiveSlots = $derived(
    [1, 2, 3, 4].map((seat) => detectives.find((player) => player.seat === seat)),
  )
  let chisel = $derived(room.players.find((player) => player.role === "chisel"))
  let canStart = $derived(detectives.length >= 2 && detectives.every((player) => player.ready))
  let isChisel = $derived(room.membership.role === "chisel")
  let settingsCapacityValid = $derived(Number(settingsMaxDetectives) >= detectives.length)

  function commandFailure(code, fallback = "Action rejected.") {
    if (code === "stale_version") return "Room changed. State refreshed; try again."
    if (code === "rate_limited") {
      return "Dispatch rejected a burst of orders. Wait a moment before transmitting again."
    }
    if (code === "invite_not_active") return "That invitation is no longer active."
    if (code === "player_not_found") return "That Detective has already left the room."
    if (code === "capacity_below_membership") {
      return "Room capacity cannot be lower than the seated Detective count."
    }
    if (code === "case_version_not_published") return "That case file is no longer published."
    return fallback
  }

  function invitationExpiry() {
    if (!room.invite?.expires_at) return t("No active expiry")

    return new Intl.DateTimeFormat(locale === "vi" ? "vi-VN" : "en-US", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(room.invite.expires_at))
  }

  function applyLobby(nextLobby, version = nextLobby.current_version) {
    if (version < room.current_version) return

    const ownPlayer = nextLobby.players.find((player) => player.id === room.membership.id)

    room = {
      ...nextLobby,
      membership: {
        ...room.membership,
        ready: ownPlayer?.ready ?? room.membership.ready,
      },
    }
  }

  function updateOnlinePlayers() {
    onlinePlayerIds = new Set(Object.keys(presenceState))
  }

  function syncPresenceState(nextState) {
    presenceState = nextState
    updateOnlinePlayers()
  }

  function syncPresenceDiff(diff) {
    const nextState = Object.fromEntries(
      Object.entries(presenceState).map(([playerId, presence]) => [
        playerId,
        { metas: (presence.metas ?? []).map((meta) => ({ ...meta })) },
      ]),
    )

    for (const [playerId, presence] of Object.entries(diff.joins ?? {})) {
      const existingMetas = nextState[playerId]?.metas ?? []
      const knownRefs = new Set(existingMetas.map((meta) => meta.phx_ref))
      const joinedMetas = (presence.metas ?? []).filter((meta) => !knownRefs.has(meta.phx_ref))
      nextState[playerId] = { metas: [...existingMetas, ...joinedMetas] }
    }

    for (const [playerId, presence] of Object.entries(diff.leaves ?? {})) {
      const leavingRefs = new Set((presence.metas ?? []).map((meta) => meta.phx_ref))
      const remainingMetas = (nextState[playerId]?.metas ?? []).filter(
        (meta) => !leavingRefs.has(meta.phx_ref),
      )

      if (remainingMetas.length === 0) delete nextState[playerId]
      else nextState[playerId] = { metas: remainingMetas }
    }

    presenceState = nextState
    updateOnlinePlayers()
  }

  function sendReady(ready) {
    if (!channel || commandPending) return

    commandPending = true
    commandError = null

    channel
      .push(ready ? "ready" : "unready", { expected_version: room.current_version })
      .receive("ok", () => {
        commandPending = false
      })
      .receive("error", ({ code }) => {
        commandPending = false
        commandError = commandFailure(code)
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Connection timed out. Try again."
      })
  }

  function startGame() {
    if (!channel || commandPending || !canStart) return

    startCommandId ??= crypto.randomUUID()
    commandPending = true
    commandError = null

    channel
      .push("start_game", {
        command_id: startCommandId,
        expected_version: room.current_version,
      })
      .receive("ok", ({ path }) => {
        window.location.assign(path)
      })
      .receive("error", ({ code }) => {
        commandPending = false

        if (code !== "stale_version") startCommandId = null

        commandError =
          code === "detectives_not_ready"
            ? "Every Detective must be ready."
            : commandFailure(code, "Game could not start.")
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Start is still unconfirmed. Retry safely."
      })
  }

  function leaveLobby() {
    if (!leaveArmed) {
      leaveArmed = true
      return
    }
    if (!channel || commandPending) return

    commandPending = true
    commandError = null
    channel
      .push("leave_lobby", { expected_version: room.current_version })
      .receive("ok", ({ path }) => window.location.assign(path))
      .receive("error", ({ code }) => {
        commandPending = false
        leaveArmed = false
        commandError = commandFailure(code, "Could not leave the room.")
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Connection timed out. Try again."
      })
  }

  function cancelLobby() {
    if (!cancelArmed) {
      cancelArmed = true
      return
    }
    if (!channel || commandPending) return

    commandPending = true
    commandError = null
    channel
      .push("cancel_lobby", { expected_version: room.current_version })
      .receive("ok", ({ path }) => window.location.assign(path))
      .receive("error", ({ code }) => {
        commandPending = false
        cancelArmed = false
        commandError = commandFailure(code, "Could not cancel the room.")
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Connection timed out. Try again."
      })
  }

  function removePlayer(playerId) {
    if (pendingRemovalId !== playerId) {
      pendingRemovalId = playerId
      return
    }
    if (!channel || commandPending) return

    commandPending = true
    commandError = null
    channel
      .push("remove_player", {
        player_id: playerId,
        expected_version: room.current_version,
      })
      .receive("ok", () => {
        commandPending = false
        pendingRemovalId = null
      })
      .receive("error", ({ code }) => {
        commandPending = false
        pendingRemovalId = null
        commandError = commandFailure(code, "Could not remove that Detective.")
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Connection timed out. Try again."
      })
  }

  function revokeInvite() {
    if (!revokeArmed) {
      revokeArmed = true
      return
    }
    if (!channel || commandPending) return

    commandPending = true
    commandError = null
    channel
      .push("revoke_invite", { expected_version: room.current_version })
      .receive("ok", () => {
        commandPending = false
        revokeArmed = false
        inviteUrl = null
        inviteCopied = false
      })
      .receive("error", ({ code }) => {
        commandPending = false
        revokeArmed = false
        commandError = commandFailure(code, "Could not revoke the invitation.")
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Connection timed out. Try again."
      })
  }

  function regenerateInvite() {
    if (!channel || commandPending) return

    commandPending = true
    commandError = null
    inviteCopied = false
    channel
      .push("regenerate_invite", {
        expected_version: room.current_version,
        invite_hours: Number(inviteHours),
      })
      .receive("ok", ({ invite_path }) => {
        commandPending = false
        revokeArmed = false
        inviteUrl = new URL(invite_path, window.location.origin).toString()
      })
      .receive("error", ({ code }) => {
        commandPending = false
        commandError = commandFailure(code, "Could not issue a new invitation.")
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Connection timed out. Try again."
      })
  }

  function toggleSettings() {
    settingsOpen = !settingsOpen
    if (settingsOpen) {
      settingsCaseVersionId = room.case_version_id
      settingsMaxDetectives = room.max_detectives
    }
  }

  function saveLobbySettings() {
    if (!channel || commandPending || !settingsCapacityValid) return

    commandPending = true
    commandError = null
    channel
      .push("update_lobby_settings", {
        case_version_id: settingsCaseVersionId,
        max_detectives: Number(settingsMaxDetectives),
        expected_version: room.current_version,
      })
      .receive("ok", () => {
        commandPending = false
        settingsOpen = false
      })
      .receive("error", ({ code }) => {
        commandPending = false
        commandError = commandFailure(code, "Could not update the room orders.")
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Connection timed out. Try again."
      })
  }

  async function copyInvite() {
    if (!inviteUrl || !navigator.clipboard) return
    await navigator.clipboard.writeText(inviteUrl)
    inviteCopied = true
  }

  function redirectRemovedPlayer({ player_id: playerId }) {
    if (playerId === room.membership.id) window.location.assign("/dashboard")
  }

  onMount(() => {
    const socket = window.getGameSocket?.()
    if (!socket) {
      connectionState = "offline"
      return
    }

    channel = socket.channel(`lobby:${room.id}`, {})
    channel.on("lobby_state", ({ lobby: nextLobby, version }) => applyLobby(nextLobby, version))
    channel.on("presence_state", syncPresenceState)
    channel.on("presence_diff", syncPresenceDiff)
    channel.on("game_started", ({ path }) => window.location.assign(path))
    channel.on("lobby_cancelled", ({ path }) => window.location.assign(path))
    channel.on("player_removed", redirectRemovedPlayer)

    channel
      .join()
      .receive("ok", ({ lobby: joinedLobby }) => {
        applyLobby(joinedLobby)
        connectionState = "online"
      })
      .receive("error", () => {
        connectionState = "unauthorized"
      })
      .receive("timeout", () => {
        connectionState = "offline"
      })

    return () => {
      channel?.leave()
      channel = null
    }
  })
</script>

<div id="lobby-shell" class="min-h-[calc(100dvh-3.5rem)] bg-[#090807] text-[#eadbbd]">
  <main class="mx-auto max-w-[90rem] px-4 py-5 sm:px-6 lg:px-8 lg:py-8">
    <header class="mb-5 flex flex-wrap items-end justify-between gap-4 px-1">
      <div>
        <p class="font-mono text-[0.65rem] uppercase tracking-[0.24em] text-[#c2a35f]">
          {t("Precinct room · {code}", { code: room.room_code })}
        </p>
        <h1 id="lobby-title" class="mt-1 font-serif text-3xl font-semibold tracking-[-0.035em] text-[#f1e4c8] sm:text-4xl">
          {room.title}
        </h1>
      </div>
      <div class="flex items-center gap-3">
        <span class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-[#a98d63]">{t("Case file v{version}", { version: room.case_version })}</span>
        <StatusStamp tone="sealed">{t(room.status)}</StatusStamp>
      </div>
    </header>

    <div class="grid min-h-[38rem] gap-5 xl:grid-cols-[minmax(0,1fr)_21rem]">
      <section
        id="lobby-player-tray"
        aria-labelledby="lobby-title"
        class="noir-wood-frame relative isolate overflow-hidden p-3 sm:p-5"
      >
        <div class="pointer-events-none absolute inset-3 rounded-[0.7rem] border border-[#c2a35f]/25 shadow-[inset_0_0_4rem_rgba(0,0,0,0.8)]"></div>
        <div class="relative grid h-full min-h-[35rem] place-items-center overflow-hidden rounded-[0.65rem] border border-black/70 bg-[#17130f] p-4 sm:p-8">
          <div class="pointer-events-none absolute inset-0 opacity-40 [background-image:radial-gradient(circle_at_center,transparent_0_20%,#080706_76%),linear-gradient(90deg,rgba(194,163,95,.07)_1px,transparent_1px),linear-gradient(rgba(194,163,95,.07)_1px,transparent_1px)] [background-size:auto,3rem_3rem,3rem_3rem]"></div>

          <div class="relative z-10 grid w-full max-w-5xl gap-5">
            <article class="noir-paper-sheet mx-auto w-full max-w-xl px-6 py-5 text-center" data-tilt="left">
              <p class="font-mono text-[0.58rem] uppercase tracking-[0.2em] text-[#8b3029]">{t("Assigned investigation")}</p>
              <h2 class="mt-2 font-serif text-2xl font-semibold text-[#2d2118] sm:text-3xl">{room.case_title}</h2>
              <div class="mx-auto mt-4 h-px max-w-48 bg-[#8e7552]"></div>
              <p class="mt-3 font-mono text-[0.62rem] uppercase tracking-[0.14em] text-[#68563f]">
                {t("{current}/{max} Detective badges issued", { current: detectives.length, max: room.max_detectives })}
              </p>
            </article>

            <ol id="lobby-player-list" aria-label={t("Detective seats")} class="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {#each detectiveSlots as player, index}
                {@const seat = index + 1}
                {@const seatOpen = seat <= room.max_detectives}
                <li
                  id={`lobby-detective-seat-${seat}`}
                  data-testid={`lobby-detective-seat-${seat}`}
                  class={[
                    "relative flex min-h-28 items-center gap-4 rounded-xl border p-4 shadow-[inset_0_0_1.5rem_rgba(0,0,0,0.7)]",
                    player
                      ? "border-[#746039] bg-[#211c17]"
                      : seatOpen
                        ? "border-dashed border-[#746039]/70 bg-black/20"
                        : "border-black/60 bg-black/40 opacity-45",
                  ]}
                >
                  {#if player}
                    <div class="relative shrink-0">
                      <PortraitToken name={player.display_name} role="detective" {seat} size="lg" />
                      <span
                        class={[
                          "absolute -bottom-1 -right-1 size-3 rounded-full border-2 border-[#17130f]",
                          onlinePlayerIds.has(player.id) ? "bg-[#61916e]" : "bg-[#554c42]",
                        ]}
                        aria-hidden="true"
                      ></span>
                    </div>
                    <div class="min-w-0 flex-1">
                      <p class="font-mono text-[0.58rem] uppercase tracking-[0.16em] text-[#9c8254]">{t("Detective {seat}", { seat })}</p>
                      <p class="mt-1 truncate font-serif text-lg font-semibold text-[#eadbbd]">{player.display_name}</p>
                      <div class="mt-2">
                        <StatusStamp tone={player.ready ? "ready" : "neutral"}>
                          {player.ready ? t("Ready") : t("Not ready")}
                        </StatusStamp>
                      </div>
                      <span class="sr-only">{onlinePlayerIds.has(player.id) ? t("Online") : t("Offline")}</span>
                    </div>
                    {#if isChisel}
                      <div class="ml-auto grid shrink-0 gap-1.5 text-right">
                        {#if pendingRemovalId === player.id}
                          <button
                            id={`lobby-confirm-remove-${player.id}`}
                            type="button"
                            disabled={connectionState !== "online" || commandPending}
                            onclick={() => removePlayer(player.id)}
                            class="rounded border border-[#8b3029] bg-[#5b1f1b] px-2.5 py-1.5 font-mono text-[0.55rem] uppercase tracking-[0.1em] text-[#f1dfbd] transition hover:bg-[#762a24] disabled:opacity-45"
                          >
                            {commandPending ? t("Removing…") : t("Confirm removal")}
                          </button>
                          <button
                            type="button"
                            disabled={commandPending}
                            onclick={() => (pendingRemovalId = null)}
                            class="px-2 py-1 font-mono text-[0.52rem] uppercase tracking-[0.1em] text-[#9c8254] underline-offset-4 hover:underline"
                          >
                            {t("Keep seated")}
                          </button>
                        {:else}
                          <button
                            id={`lobby-remove-${player.id}`}
                            type="button"
                            disabled={commandPending}
                            onclick={() => removePlayer(player.id)}
                            class="rounded border border-[#746039]/70 bg-black/20 px-2.5 py-1.5 font-mono text-[0.52rem] uppercase tracking-[0.1em] text-[#b89b68] transition hover:border-[#8b3029] hover:text-[#d9b98a] disabled:opacity-45"
                          >
                            {t("Remove")}
                          </button>
                        {/if}
                      </div>
                    {/if}
                  {:else}
                    <div class="grid size-20 shrink-0 place-items-center rounded-full border border-dashed border-[#746039]/60 bg-black/25 font-serif text-3xl text-[#746039]">
                      {seat}
                    </div>
                    <div>
                      <p class="font-mono text-[0.58rem] uppercase tracking-[0.16em] text-[#746039]">{t("Detective {seat}", { seat })}</p>
                      <p class="mt-1 font-serif text-lg text-[#b59c70]">{seatOpen ? t("Open seat") : t("Closed seat")}</p>
                      <p class="mt-1 text-xs text-[#756853]">{seatOpen ? t("Awaiting an investigator") : t("Outside room capacity")}</p>
                    </div>
                  {/if}
                </li>
              {/each}
            </ol>
          </div>
        </div>
      </section>

      <aside class="grid content-start gap-5">
        <section
          data-testid="lobby-chisel-seat"
          aria-labelledby="chisel-seat-title"
          class="noir-wood-frame overflow-hidden p-3"
        >
          <div class="rounded-[0.65rem] border border-black/60 bg-[#13100d] p-5 shadow-[inset_0_0_2rem_rgba(0,0,0,0.72)]">
            <div class="flex items-center justify-between gap-3">
              <p class="font-mono text-[0.6rem] uppercase tracking-[0.18em] text-[#c2a35f]">{t("Chisel console")}</p>
              <span
                class={[
                  "size-2.5 rounded-full shadow-[0_0_0.7rem_currentColor]",
                  chisel && onlinePlayerIds.has(chisel.id) ? "bg-[#61916e] text-[#61916e]" : "bg-[#554c42] text-[#554c42]",
                ]}
                aria-hidden="true"
              ></span>
            </div>

            {#if chisel}
              <div class="mt-5 flex items-center gap-4">
                <PortraitToken name={chisel.display_name} role="chisel" size="lg" />
                <div class="min-w-0">
                  <h2 id="chisel-seat-title" class="truncate font-serif text-xl font-semibold text-[#eadbbd]">{chisel.display_name}</h2>
                  <p class="mt-1 font-mono text-[0.6rem] uppercase tracking-[0.14em] text-[#9c8254]">{t("Keeper of the casebook")}</p>
                  <span class="sr-only">{onlinePlayerIds.has(chisel.id) ? t("Online") : t("Offline")}</span>
                </div>
              </div>
            {:else}
              <h2 id="chisel-seat-title" class="mt-5 font-serif text-xl text-[#eadbbd]">{t("Chisel unavailable")}</h2>
            {/if}
          </div>
        </section>

        {#if isChisel}
          <section id="lobby-invite-controls" aria-labelledby="invite-controls-title" class="noir-paper-sheet p-5" data-tilt="right">
            <div class="flex items-start justify-between gap-3 border-b border-[#a98d63] pb-3">
              <div>
                <p class="font-mono text-[0.55rem] uppercase tracking-[0.16em] text-[#8b3029]">{t("Dispatch desk")}</p>
                <h2 id="invite-controls-title" class="mt-1 font-serif text-xl font-semibold text-[#35271d]">{t("Invitation orders")}</h2>
              </div>
              <StatusStamp tone={room.invite?.status === "active" ? "ready" : "neutral"}>
                {t(`invite ${room.invite?.status ?? "unavailable"}`)}
              </StatusStamp>
            </div>

            <dl class="mt-4 grid grid-cols-[auto_1fr] gap-x-3 gap-y-2 text-xs text-[#5f4b39]">
              <dt class="font-mono uppercase tracking-[0.1em] text-[#7d654a]">{t("Expires")}</dt>
              <dd class="text-right">{invitationExpiry()}</dd>
              <dt class="font-mono uppercase tracking-[0.1em] text-[#7d654a]">{t("Uses left")}</dt>
              <dd class="text-right">{room.invite?.uses_remaining ?? 0}</dd>
            </dl>

            {#if inviteUrl}
              <div class="mt-4 border-y border-[#a98d63]/60 py-3">
                <label for="lobby-invite-url" class="font-mono text-[0.55rem] uppercase tracking-[0.12em] text-[#6d533c]">
                  {t("One-time dispatch copy")}
                </label>
                <input
                  id="lobby-invite-url"
                  readonly
                  value={inviteUrl}
                  class="mt-2 w-full border border-[#9c805b] bg-[#efe1c2]/70 px-2.5 py-2 font-mono text-[0.68rem] text-[#39291f] outline-none focus:border-[#6b4c31]"
                />
                <button
                  id="lobby-copy-invite"
                  type="button"
                  onclick={copyInvite}
                  class="mt-2 w-full border border-[#6d533c] bg-[#d5c09a] px-3 py-2 font-mono text-[0.58rem] font-semibold uppercase tracking-[0.12em] text-[#3b2a1e] transition hover:bg-[#cbb183]"
                >
                  {inviteCopied ? t("Copied") : t("Copy invitation")}
                </button>
              </div>
            {:else}
              <p class="mt-4 border-l-2 border-[#8b3029]/70 pl-3 text-xs leading-5 text-[#6b5540]">
                {t("The raw link stays sealed. Issue a replacement to reveal it once.")}
              </p>
            {/if}

            <div class="mt-4 grid grid-cols-[1fr_auto] gap-2">
              <label for="lobby-invite-expiry" class="sr-only">{t("Invite expires")}</label>
              <select
                id="lobby-invite-expiry"
                bind:value={inviteHours}
                disabled={commandPending}
                class="border border-[#8e7552] bg-[#ead8b5] px-3 py-2 font-mono text-[0.62rem] uppercase tracking-[0.08em] text-[#49372a] outline-none focus:border-[#6b4c31] disabled:opacity-50"
              >
                <option value={1}>{t("1 hour")}</option>
                <option value={6}>{t("6 hours")}</option>
                <option value={24}>{t("24 hours")}</option>
                <option value={72}>{t("3 days")}</option>
              </select>
              <button
                id="lobby-regenerate-invite"
                type="button"
                disabled={connectionState !== "online" || commandPending}
                onclick={regenerateInvite}
                class="border border-[#5a422e] bg-[#3f2d20] px-3 py-2 font-mono text-[0.58rem] font-semibold uppercase tracking-[0.1em] text-[#eadbbd] transition hover:bg-[#523927] disabled:opacity-45"
              >
                {commandPending ? t("Sealing…") : room.invite?.status === "active" ? t("Replace") : t("Issue")}
              </button>
            </div>

            {#if room.invite?.status === "active"}
              <div class="mt-3">
                {#if revokeArmed}
                  <div class="grid grid-cols-2 gap-2">
                    <button
                      id="lobby-confirm-revoke-invite"
                      type="button"
                      disabled={connectionState !== "online" || commandPending}
                      onclick={revokeInvite}
                      class="border border-[#8b3029] bg-[#6b241e] px-3 py-2 font-mono text-[0.56rem] font-semibold uppercase tracking-[0.1em] text-[#f1dfbd] transition hover:bg-[#812d25] disabled:opacity-45"
                    >
                      {t("Confirm revoke")}
                    </button>
                    <button
                      type="button"
                      disabled={commandPending}
                      onclick={() => (revokeArmed = false)}
                      class="border border-[#8e7552] px-3 py-2 font-mono text-[0.56rem] uppercase tracking-[0.1em] text-[#624a36] transition hover:bg-[#d9c6a2]"
                    >
                      {t("Keep active")}
                    </button>
                  </div>
                {:else}
                  <button
                    id="lobby-revoke-invite"
                    type="button"
                    disabled={commandPending}
                    onclick={revokeInvite}
                    class="w-full border border-[#8b3029]/55 px-3 py-2 font-mono text-[0.56rem] uppercase tracking-[0.1em] text-[#752b25] transition hover:bg-[#8b3029]/10 disabled:opacity-45"
                  >
                    {t("Revoke current invitation")}
                  </button>
                {/if}
              </div>
            {/if}
          </section>
        {/if}

        <section id="lobby-controls" aria-labelledby="lobby-controls-title" class="noir-paper-sheet p-5">
          <div class="flex items-center justify-between gap-3 border-b border-[#a98d63] pb-3">
            <h2 id="lobby-controls-title" class="font-mono text-[0.62rem] font-semibold uppercase tracking-[0.16em] text-[#49372a]">
              {t("Briefing controls")}
            </h2>
            <span class={connectionState === "online" ? "text-[#355844]" : "text-[#7d6b55]"}>
              <span class="sr-only">{t("Realtime link:")}</span>
              <span class="font-mono text-[0.58rem] uppercase tracking-[0.12em]">{t(connectionState)}</span>
            </span>
          </div>

          <p class="mt-4 text-sm leading-6 text-[#5f4b39]">
            {room.membership.role === "detective"
              ? t("Mark your badge ready when you have reviewed the case assignment.")
              : t("Briefing may begin once every seated Detective has marked ready.")}
          </p>

          {#if isChisel}
            <div class="mt-4 border-y border-[#a98d63]/70 py-3">
              <button
                id="lobby-toggle-settings"
                type="button"
                disabled={commandPending}
                onclick={toggleSettings}
                class="flex w-full items-center justify-between gap-3 text-left font-mono text-[0.58rem] font-semibold uppercase tracking-[0.12em] text-[#624a36] transition hover:text-[#8b3029] disabled:opacity-45"
              >
                <span>{t("Room orders")}</span>
                <span aria-hidden="true">{settingsOpen ? "−" : "+"}</span>
              </button>

              {#if settingsOpen}
                <div id="lobby-settings-panel" class="mt-4 grid gap-4">
                  <div>
                    <label for="lobby-case-version" class="font-mono text-[0.54rem] uppercase tracking-[0.1em] text-[#765c42]">
                      {t("Assigned case file")}
                    </label>
                    <select
                      id="lobby-case-version"
                      bind:value={settingsCaseVersionId}
                      disabled={commandPending}
                      class="mt-1.5 w-full border border-[#8e7552] bg-[#ead8b5] px-3 py-2 text-sm text-[#49372a] outline-none focus:border-[#6b4c31] disabled:opacity-50"
                    >
                      {#each case_options as option (option.value)}
                        <option value={option.value}>{option.label}</option>
                      {/each}
                    </select>
                  </div>

                  <div>
                    <label for="lobby-max-detectives" class="font-mono text-[0.54rem] uppercase tracking-[0.1em] text-[#765c42]">
                      {t("Detective seats")}
                    </label>
                    <select
                      id="lobby-max-detectives"
                      bind:value={settingsMaxDetectives}
                      disabled={commandPending}
                      class="mt-1.5 w-full border border-[#8e7552] bg-[#ead8b5] px-3 py-2 text-sm text-[#49372a] outline-none focus:border-[#6b4c31] disabled:opacity-50"
                    >
                      {#each [2, 3, 4] as count}
                        <option value={count}>{t("{count} detectives", { count })}</option>
                      {/each}
                    </select>
                    {#if !settingsCapacityValid}
                      <p id="lobby-settings-capacity-error" class="mt-2 text-xs leading-5 text-[#7a2b25]">
                        {t("Room capacity cannot be lower than the seated Detective count.")}
                      </p>
                    {/if}
                  </div>

                  <div class="grid grid-cols-2 gap-2">
                    <button
                      id="lobby-save-settings"
                      type="button"
                      disabled={connectionState !== "online" || commandPending || !settingsCapacityValid || case_options.length === 0}
                      onclick={saveLobbySettings}
                      class="border border-[#5a422e] bg-[#3f2d20] px-3 py-2 font-mono text-[0.56rem] font-semibold uppercase tracking-[0.1em] text-[#eadbbd] transition hover:bg-[#523927] disabled:opacity-45"
                    >
                      {commandPending ? t("Sealing…") : t("Seal changes")}
                    </button>
                    <button
                      type="button"
                      disabled={commandPending}
                      onclick={toggleSettings}
                      class="border border-[#8e7552] px-3 py-2 font-mono text-[0.56rem] uppercase tracking-[0.1em] text-[#624a36] transition hover:bg-[#d9c6a2] disabled:opacity-45"
                    >
                      {t("Cancel")}
                    </button>
                  </div>
                  <p class="text-[0.68rem] leading-5 text-[#715a42]">
                    {t("Published cases and room capacity may change only before briefing begins.")}
                  </p>
                </div>
              {/if}
            </div>
          {/if}

          <div class="mt-5">
            {#if room.membership.role === "detective"}
              <button
                id={room.membership.ready ? "lobby-unready" : "lobby-ready"}
                type="button"
                disabled={connectionState !== "online" || commandPending}
                onclick={() => sendReady(!room.membership.ready)}
                class="noir-physical-button w-full px-4 py-3 text-sm font-semibold"
              >
                {commandPending ? t("Updating…") : room.membership.ready ? t("Stand down") : t("Ready for briefing")}
              </button>
            {:else}
              <button
                id="lobby-start-game"
                type="button"
                disabled={connectionState !== "online" || commandPending || !canStart}
                onclick={startGame}
                class="noir-physical-button w-full px-4 py-3 text-sm font-semibold"
              >
                {commandPending ? t("Opening casebook…") : canStart ? t("Start briefing") : t("Waiting for Detectives")}
              </button>
            {/if}
          </div>

          {#if commandError}
            <p id="lobby-command-error" class="mt-3 border-l-2 border-[#8b3029] pl-3 text-sm text-[#6b211c]" role="alert">
              {t(commandError)}
            </p>
          {/if}

          {#if room.membership.role === "detective"}
            <div class="mt-5 border-t border-[#a98d63]/70 pt-4">
              {#if leaveArmed}
                <p class="mb-3 text-xs leading-5 text-[#6b211c]">
                  {t("Leaving releases your badge. A valid invitation can admit you again.")}
                </p>
                <div class="grid grid-cols-2 gap-2">
                  <button
                    id="lobby-confirm-leave"
                    type="button"
                    disabled={connectionState !== "online" || commandPending}
                    onclick={leaveLobby}
                    class="border border-[#8b3029] bg-[#6b241e] px-3 py-2 font-mono text-[0.56rem] font-semibold uppercase tracking-[0.1em] text-[#f1dfbd] transition hover:bg-[#812d25] disabled:opacity-45"
                  >
                    {commandPending ? t("Leaving…") : t("Confirm exit")}
                  </button>
                  <button
                    type="button"
                    disabled={commandPending}
                    onclick={() => (leaveArmed = false)}
                    class="border border-[#8e7552] px-3 py-2 font-mono text-[0.56rem] uppercase tracking-[0.1em] text-[#624a36] transition hover:bg-[#d9c6a2]"
                  >
                    {t("Stay in room")}
                  </button>
                </div>
              {:else}
                <button
                  id="lobby-leave"
                  type="button"
                  disabled={commandPending}
                  onclick={leaveLobby}
                  class="w-full border border-[#8b3029]/55 px-3 py-2 font-mono text-[0.56rem] uppercase tracking-[0.1em] text-[#752b25] transition hover:bg-[#8b3029]/10 disabled:opacity-45"
                >
                  {t("Leave investigation room")}
                </button>
              {/if}
            </div>
          {:else}
            <div class="mt-5 border-t border-[#a98d63]/70 pt-4">
              {#if cancelArmed}
                <p class="mb-3 text-xs leading-5 text-[#6b211c]">
                  {t("Cancelling revokes every invitation and permanently closes this waiting room.")}
                </p>
                <div class="grid grid-cols-2 gap-2">
                  <button
                    id="lobby-confirm-cancel"
                    type="button"
                    disabled={connectionState !== "online" || commandPending}
                    onclick={cancelLobby}
                    class="border border-[#8b3029] bg-[#6b241e] px-3 py-2 font-mono text-[0.56rem] font-semibold uppercase tracking-[0.1em] text-[#f1dfbd] transition hover:bg-[#812d25] disabled:opacity-45"
                  >
                    {commandPending ? t("Closing…") : t("Seal cancellation")}
                  </button>
                  <button
                    type="button"
                    disabled={commandPending}
                    onclick={() => (cancelArmed = false)}
                    class="border border-[#8e7552] px-3 py-2 font-mono text-[0.56rem] uppercase tracking-[0.1em] text-[#624a36] transition hover:bg-[#d9c6a2]"
                  >
                    {t("Keep room")}
                  </button>
                </div>
              {:else}
                <button
                  id="lobby-cancel-room"
                  type="button"
                  disabled={commandPending}
                  onclick={cancelLobby}
                  class="w-full border border-[#8b3029]/55 px-3 py-2 font-mono text-[0.56rem] uppercase tracking-[0.1em] text-[#752b25] transition hover:bg-[#8b3029]/10 disabled:opacity-45"
                >
                  {t("Cancel waiting room")}
                </button>
              {/if}
            </div>
          {/if}
        </section>
      </aside>
    </div>
  </main>
</div>
