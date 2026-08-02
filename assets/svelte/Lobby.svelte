<script>
  import { onMount } from "svelte"

  let { lobby } = $props()

  const initialLobby = () => lobby

  let room = $state(initialLobby())
  let onlinePlayerIds = $state(new Set())
  let presenceState = $state({})
  let channel = null
  let connectionState = $state("connecting")
  let commandPending = $state(false)
  let commandError = $state(null)
  let startCommandId = null

  let detectives = $derived(room.players.filter((player) => player.role === "detective"))
  let canStart = $derived(detectives.length > 0 && detectives.every((player) => player.ready))

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
        commandError = code === "stale_version" ? "Room changed. State refreshed; try again." : "Action rejected."
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
            : code === "stale_version"
              ? "Room changed. State refreshed; try again."
              : "Game could not start."
      })
      .receive("timeout", () => {
        commandPending = false
        commandError = "Start is still unconfirmed. Retry safely."
      })
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

<div id="lobby-shell" class="min-h-[calc(100dvh-3.5rem)] bg-[#0b0d0e] text-stone-100">
  <main class="mx-auto grid max-w-7xl gap-8 px-4 py-8 sm:px-6 lg:grid-cols-[minmax(0,1.35fr)_minmax(22rem,0.65fr)] lg:px-8 lg:py-12">
    <section id="lobby-board" aria-labelledby="lobby-title" class="min-w-0">
      <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.2em] text-[#e06a5b]">Room {room.room_code}</p>
          <h1 id="lobby-title" class="mt-2 font-serif text-3xl font-semibold tracking-[-0.035em] sm:text-4xl">
            {room.title}
          </h1>
          <p class="mt-2 text-sm text-stone-400">{room.case_title} · case file v{room.case_version}</p>
        </div>
        <span class="border border-white/15 px-3 py-1.5 font-mono text-xs uppercase tracking-[0.16em] text-stone-300">
          {room.status}
        </span>
      </div>

      <div class="relative min-h-[31rem] overflow-hidden border border-white/10 bg-[#121617]">
        <svg
          id="lobby-table-scene"
          class="absolute inset-0 size-full"
          viewBox="0 0 900 600"
          preserveAspectRatio="xMidYMid meet"
          role="img"
          aria-labelledby="lobby-scene-title lobby-scene-desc"
        >
          <title id="lobby-scene-title">Investigation table</title>
          <desc id="lobby-scene-desc">An original evidence table showing seats occupied by room players.</desc>
          <defs>
            <pattern id="lobby-grid" width="28" height="28" patternUnits="userSpaceOnUse">
              <path d="M28 0H0V28" fill="none" stroke="#2f3536" stroke-width="1" />
            </pattern>
          </defs>
          <rect width="900" height="600" fill="#121617" />
          <rect width="900" height="600" fill="url(#lobby-grid)" opacity="0.7" />
          <ellipse cx="450" cy="314" rx="320" ry="210" fill="#191e20" stroke="#596061" stroke-width="2" />
          <ellipse cx="450" cy="314" rx="268" ry="164" fill="none" stroke="#303738" stroke-width="2" stroke-dasharray="8 12" />
          <path d="M450 150v328M184 314h532" stroke="#303738" stroke-width="1" />
          <g transform="translate(350 235) rotate(-4)">
            <rect width="200" height="146" fill="#d8d1c4" />
            <path d="M22 30h112M22 50h156M22 76h156M22 96h110" stroke="#777064" stroke-width="3" />
            <circle cx="154" cy="112" r="21" fill="none" stroke="#bd4b40" stroke-width="4" />
          </g>

          {#each room.players as player, index}
            {@const positions = [[450, 78], [770, 314], [450, 550], [130, 314], [690, 105]]}
            {@const position = positions[index] ?? [450, 314]}
            <g id={`lobby-player-token-${player.id}`} transform={`translate(${position[0]} ${position[1]})`}>
              <circle
                r="34"
                fill={player.role === "chisel" ? "#cf5547" : "#d7d1c5"}
                stroke="#0b0d0e"
                stroke-width="7"
              />
              <text
                y="5"
                text-anchor="middle"
                fill="#0b0d0e"
                font-family="ui-monospace, monospace"
                font-size="12"
                font-weight="700"
              >
                {player.role === "chisel" ? "HOST" : `D${player.seat ?? index}`}
              </text>
            </g>
          {/each}
        </svg>
      </div>
    </section>

    <aside class="border-t border-white/10 pt-8 lg:border-l lg:border-t-0 lg:pl-8 lg:pt-0">
      <section id="lobby-player-list" aria-labelledby="players-title">
        <div class="flex items-center justify-between gap-4">
          <h2 id="players-title" class="text-sm font-semibold uppercase tracking-[0.14em] text-stone-300">
            At the table
          </h2>
          <span class="font-mono text-xs text-stone-500">
            {room.players.filter((player) => player.role === "detective").length}/{room.max_detectives} detectives
          </span>
        </div>

        <ul class="mt-4 divide-y divide-white/10 border-y border-white/10">
          {#each room.players as player}
            <li id={`lobby-player-${player.id}`} class="flex items-center gap-3 py-4">
              <span
                class={`size-2.5 rounded-full ${onlinePlayerIds.has(player.id) ? "bg-emerald-400" : "bg-stone-700"}`}
                aria-hidden="true"
              ></span>
              <span class="min-w-0 flex-1 truncate text-sm text-stone-200">{player.display_name}</span>
              <span class={`font-mono text-[10px] uppercase tracking-[0.1em] ${player.ready ? "text-emerald-300" : "text-stone-600"}`}>
                {player.role === "chisel" ? "Host" : player.ready ? "Ready" : "Not ready"}
              </span>
              <span class="font-mono text-[11px] uppercase tracking-[0.12em] text-stone-500">{player.role}</span>
              <span class="sr-only">{onlinePlayerIds.has(player.id) ? "Online" : "Offline"}</span>
            </li>
          {/each}
        </ul>
      </section>

      <section id="lobby-controls" class="mt-8 border-t border-white/10 pt-6">
        <div class="mb-3 flex items-center justify-between gap-3 font-mono text-[11px] uppercase tracking-[0.12em]">
          <span class="text-stone-500">Realtime link</span>
          <span class={connectionState === "online" ? "text-emerald-300" : "text-stone-500"}>{connectionState}</span>
        </div>

        {#if room.membership.role === "detective"}
          <button
            id={room.membership.ready ? "lobby-unready" : "lobby-ready"}
            type="button"
            disabled={connectionState !== "online" || commandPending}
            onclick={() => sendReady(!room.membership.ready)}
            class="w-full cursor-pointer bg-[#e06a5b] px-4 py-3 text-sm font-semibold text-[#0b0d0e] transition hover:bg-[#ef7a6a] disabled:cursor-not-allowed disabled:bg-stone-700 disabled:text-stone-400"
          >
            {commandPending ? "Updating…" : room.membership.ready ? "Stand down" : "Ready for briefing"}
          </button>
        {:else}
          <button
            id="lobby-start-game"
            type="button"
            disabled={connectionState !== "online" || commandPending || !canStart}
            onclick={startGame}
            class="w-full cursor-pointer bg-[#e06a5b] px-4 py-3 text-sm font-semibold text-[#0b0d0e] transition hover:bg-[#ef7a6a] disabled:cursor-not-allowed disabled:bg-stone-700 disabled:text-stone-400"
          >
            {commandPending ? "Opening casebook…" : canStart ? "Start briefing" : "Waiting for Detectives"}
          </button>
        {/if}

        {#if commandError}
          <p id="lobby-command-error" class="mt-3 text-sm text-[#ff9b8f]" role="alert">{commandError}</p>
        {/if}
      </section>
    </aside>
  </main>
</div>
