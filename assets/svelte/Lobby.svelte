<script>
  import { onMount } from "svelte"

  import PortraitToken from "./ui/PortraitToken.svelte"
  import StatusStamp from "./ui/StatusStamp.svelte"

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
  let detectiveSlots = $derived(
    [1, 2, 3, 4].map((seat) => detectives.find((player) => player.seat === seat)),
  )
  let chisel = $derived(room.players.find((player) => player.role === "chisel"))
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

<div id="lobby-shell" class="min-h-[calc(100dvh-3.5rem)] bg-[#090807] text-[#eadbbd]">
  <main class="mx-auto max-w-[90rem] px-4 py-5 sm:px-6 lg:px-8 lg:py-8">
    <header class="mb-5 flex flex-wrap items-end justify-between gap-4 px-1">
      <div>
        <p class="font-mono text-[0.65rem] uppercase tracking-[0.24em] text-[#c2a35f]">
          Precinct room · {room.room_code}
        </p>
        <h1 id="lobby-title" class="mt-1 font-serif text-3xl font-semibold tracking-[-0.035em] text-[#f1e4c8] sm:text-4xl">
          {room.title}
        </h1>
      </div>
      <div class="flex items-center gap-3">
        <span class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-[#a98d63]">Case file v{room.case_version}</span>
        <StatusStamp tone="sealed">{room.status}</StatusStamp>
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
              <p class="font-mono text-[0.58rem] uppercase tracking-[0.2em] text-[#8b3029]">Assigned investigation</p>
              <h2 class="mt-2 font-serif text-2xl font-semibold text-[#2d2118] sm:text-3xl">{room.case_title}</h2>
              <div class="mx-auto mt-4 h-px max-w-48 bg-[#8e7552]"></div>
              <p class="mt-3 font-mono text-[0.62rem] uppercase tracking-[0.14em] text-[#68563f]">
                {detectives.length}/{room.max_detectives} Detective badges issued
              </p>
            </article>

            <ol id="lobby-player-list" aria-label="Detective seats" class="grid grid-cols-1 gap-3 sm:grid-cols-2">
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
                      <p class="font-mono text-[0.58rem] uppercase tracking-[0.16em] text-[#9c8254]">Detective {seat}</p>
                      <p class="mt-1 truncate font-serif text-lg font-semibold text-[#eadbbd]">{player.display_name}</p>
                      <div class="mt-2">
                        <StatusStamp tone={player.ready ? "ready" : "neutral"}>
                          {player.ready ? "Ready" : "Not ready"}
                        </StatusStamp>
                      </div>
                      <span class="sr-only">{onlinePlayerIds.has(player.id) ? "Online" : "Offline"}</span>
                    </div>
                  {:else}
                    <div class="grid size-20 shrink-0 place-items-center rounded-full border border-dashed border-[#746039]/60 bg-black/25 font-serif text-3xl text-[#746039]">
                      {seat}
                    </div>
                    <div>
                      <p class="font-mono text-[0.58rem] uppercase tracking-[0.16em] text-[#746039]">Detective {seat}</p>
                      <p class="mt-1 font-serif text-lg text-[#b59c70]">{seatOpen ? "Open seat" : "Closed seat"}</p>
                      <p class="mt-1 text-xs text-[#756853]">{seatOpen ? "Awaiting an investigator" : "Outside room capacity"}</p>
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
              <p class="font-mono text-[0.6rem] uppercase tracking-[0.18em] text-[#c2a35f]">Chisel console</p>
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
                  <p class="mt-1 font-mono text-[0.6rem] uppercase tracking-[0.14em] text-[#9c8254]">Keeper of the casebook</p>
                  <span class="sr-only">{onlinePlayerIds.has(chisel.id) ? "Online" : "Offline"}</span>
                </div>
              </div>
            {:else}
              <h2 id="chisel-seat-title" class="mt-5 font-serif text-xl text-[#eadbbd]">Chisel unavailable</h2>
            {/if}
          </div>
        </section>

        <section id="lobby-controls" aria-labelledby="lobby-controls-title" class="noir-paper-sheet p-5">
          <div class="flex items-center justify-between gap-3 border-b border-[#a98d63] pb-3">
            <h2 id="lobby-controls-title" class="font-mono text-[0.62rem] font-semibold uppercase tracking-[0.16em] text-[#49372a]">
              Briefing controls
            </h2>
            <span class={connectionState === "online" ? "text-[#355844]" : "text-[#7d6b55]"}>
              <span class="sr-only">Realtime link:</span>
              <span class="font-mono text-[0.58rem] uppercase tracking-[0.12em]">{connectionState}</span>
            </span>
          </div>

          <p class="mt-4 text-sm leading-6 text-[#5f4b39]">
            {room.membership.role === "detective"
              ? "Mark your badge ready when you have reviewed the case assignment."
              : "Briefing may begin once every seated Detective has marked ready."}
          </p>

          <div class="mt-5">
            {#if room.membership.role === "detective"}
              <button
                id={room.membership.ready ? "lobby-unready" : "lobby-ready"}
                type="button"
                disabled={connectionState !== "online" || commandPending}
                onclick={() => sendReady(!room.membership.ready)}
                class="noir-physical-button w-full px-4 py-3 text-sm font-semibold"
              >
                {commandPending ? "Updating…" : room.membership.ready ? "Stand down" : "Ready for briefing"}
              </button>
            {:else}
              <button
                id="lobby-start-game"
                type="button"
                disabled={connectionState !== "online" || commandPending || !canStart}
                onclick={startGame}
                class="noir-physical-button w-full px-4 py-3 text-sm font-semibold"
              >
                {commandPending ? "Opening casebook…" : canStart ? "Start briefing" : "Waiting for Detectives"}
              </button>
            {/if}
          </div>

          {#if commandError}
            <p id="lobby-command-error" class="mt-3 border-l-2 border-[#8b3029] pl-3 text-sm text-[#6b211c]" role="alert">
              {commandError}
            </p>
          {/if}
        </section>
      </aside>
    </div>
  </main>
</div>
