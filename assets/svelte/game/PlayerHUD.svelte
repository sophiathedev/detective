<script>
  let {
    players = [],
    currentDetectiveId = null,
    privateState = {},
    onlinePlayerIds = [],
    connectionSnapshotReceived = false,
    disconnectLabel = () => "OFFLINE",
  } = $props()

  let detectiveSlots = $derived(
    [1, 2, 3, 4].map((seat) => players.find((player) => player.role === "detective" && player.seat === seat)),
  )
  let chisel = $derived(players.find((player) => player.role === "chisel"))
  let ownDetectiveId = $derived(privateState.role === "detective" ? privateState.player_id : null)
  let chiselPrivate = $derived(
    privateState.role === "chisel" && privateState.player_id === chisel?.id,
  )

  function connectionLabel(playerId) {
    if (!connectionSnapshotReceived) return "SYNCING"
    if (onlinePlayerIds.includes(playerId)) return "ONLINE"
    const detail = disconnectLabel(playerId)
    return detail && detail !== "OFFLINE" ? `OFFLINE ${detail}` : "OFFLINE"
  }

  function connectionClass(playerId, dark = false) {
    if (!connectionSnapshotReceived) return dark ? "text-[#c5ae8c]" : "text-[#715d47]"
    if (onlinePlayerIds.includes(playerId)) return dark ? "text-[#a7c2a4]" : "text-[#375845]"
    return dark ? "text-[#e78373]" : "text-[#973b32]"
  }

  function privateDetectiveLeverage() {
    const committed = Object.values(privateState.leverage_on_suspects ?? {}).reduce(
      (sum, value) => sum + value,
      0,
    )

    return (privateState.leverage_supply ?? 0) + committed
  }

  function portraitColor(seat) {
    return ["#29475a", "#704239", "#3e5c43", "#685234"][seat - 1] ?? "#4d4439"
  }
</script>

<div id="player-hud" class="player-hud-scroll border-b border-[#9f896d] bg-[#b9a78a]">
  <div class="player-hud-grid grid">
    {#each detectiveSlots as detective, index}
      {@const seat = index + 1}
      <article
        id={`detective-hud-${seat}`}
        data-testid={`detective-slot-${seat}`}
        class={`player-hud-slot relative border-r border-[#91795e] px-3 py-2.5 ${detective?.id === currentDetectiveId ? "player-hud-slot-active bg-[#f0e3c8]" : "bg-[#cbbb9d]"}`}
        aria-current={detective?.id === currentDetectiveId ? "true" : undefined}
      >
        {#if detective}
          <div class="flex items-start gap-2.5">
            <svg
              class="size-12 shrink-0 border border-[#6f5942] bg-[#2a211a]"
              viewBox="0 0 64 64"
              role="img"
              aria-label={`Portrait token for ${detective.display_name}`}
            >
              <rect width="64" height="64" fill={portraitColor(seat)} />
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
              <text
                x="52"
                y="58"
                text-anchor="end"
                fill="#f8ecd2"
                font-family="IBM Plex Mono, monospace"
                font-size="10"
                font-weight="600"
              >D{seat}</text>
            </svg>

            <div class="min-w-0 flex-1">
              <div class="flex items-start justify-between gap-2">
                <p class="truncate font-serif text-sm font-semibold text-[#30251c]">
                  {detective.display_name}
                </p>
              <span
                class={`font-mono text-[8px] font-semibold tracking-[0.08em] ${connectionClass(detective.id)}`}
                role={connectionSnapshotReceived && !onlinePlayerIds.includes(detective.id) ? "timer" : undefined}
              >{connectionLabel(detective.id)}</span>
              </div>
              <div class="mt-1.5 flex items-center gap-3 font-mono text-[10px] text-[#5f4d3b]">
                <span>AP {detective.actions_remaining}/4</span>
                <span>LOC {detective.location_id ?? "—"}</span>
              </div>
              {#if ownDetectiveId === detective.id}
                <div class="mt-2 flex flex-wrap gap-x-3 gap-y-1 border-t border-[#9e876a] pt-1.5 font-mono text-[9px] font-semibold uppercase tracking-[0.04em] text-[#7c332d]">
                  <span>Scratch {privateState.scratch ?? 0}</span>
                  <span>Leverage {privateDetectiveLeverage()}</span>
                </div>
              {/if}
            </div>
          </div>
          {#if detective.id === currentDetectiveId}
            <span class="absolute inset-x-0 bottom-0 h-1 bg-[#a54235]" aria-hidden="true"></span>
          {/if}
        {:else}
          <div class="flex min-h-16 items-center justify-center border border-dashed border-[#8d765d] font-mono text-[9px] uppercase tracking-[0.1em] text-[#7a674f]">
            D{seat} · Open dossier
          </div>
        {/if}
      </article>
    {/each}

    <article
      id="chisel-hud"
      data-testid="chisel-slot"
      class="player-hud-slot player-hud-chisel relative bg-[#352820] px-3 py-2.5 text-[#efe0c3]"
    >
      {#if chisel}
        <div class="flex items-start gap-2.5">
          <svg
            class="size-12 shrink-0 border border-[#8f7153] bg-[#19130f]"
            viewBox="0 0 64 64"
            role="img"
            aria-label={`Chisel dossier for ${chisel.display_name}`}
          >
            <rect width="64" height="64" fill="#211813" />
            <path d="M18 49 43 13l7 5-25 36Z" fill="#c7aa7d" />
            <path d="m39 12 7-5 11 8-7 6Z" fill="#7f322c" />
            <path d="M13 52h37" stroke="#efe0c3" stroke-width="2" opacity="0.75" />
          </svg>
          <div class="min-w-0 flex-1">
            <div class="flex items-start justify-between gap-2">
              <p class="truncate font-serif text-sm font-semibold">{chisel.display_name}</p>
              <span
                class={`font-mono text-[8px] font-semibold tracking-[0.08em] ${connectionClass(chisel.id, true)}`}
                role={connectionSnapshotReceived && !onlinePlayerIds.includes(chisel.id) ? "timer" : undefined}
              >{connectionLabel(chisel.id)}</span>
            </div>
            <p class="mt-1 font-mono text-[9px] uppercase tracking-[0.1em] text-[#c9aa7b]">
              Chisel dossier
            </p>
            {#if chiselPrivate}
              <p class="mt-1.5 font-mono text-[9px] font-semibold uppercase tracking-[0.06em] text-[#f1cf9b]">
                {privateState.pending_interrogation ? "Response open" : "No pending response"}
              </p>
              <div class="mt-1.5 flex flex-wrap gap-x-2 gap-y-1 border-t border-[#70533d] pt-1.5 font-mono text-[9px] text-[#e4c493]">
                {#each detectiveSlots as detective, index}
                  {#if detective}
                    <span>D{index + 1} {privateState.leverage_by_detective?.[detective.id] ?? 0}</span>
                  {/if}
                {/each}
              </div>
            {:else}
              <p class="mt-2 text-[10px] leading-4 text-[#c5ae8c]">Private controls remain sealed.</p>
            {/if}
          </div>
        </div>
      {:else}
        <div class="flex min-h-16 items-center justify-center border border-dashed border-[#806149] font-mono text-[9px] uppercase tracking-[0.1em] text-[#b99a72]">
          Chisel dossier unavailable
        </div>
      {/if}
    </article>
  </div>
</div>
