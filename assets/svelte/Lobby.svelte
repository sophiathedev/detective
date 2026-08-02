<script>
  let { lobby } = $props()
</script>

<div id="lobby-shell" class="min-h-[calc(100dvh-3.5rem)] bg-[#0b0d0e] text-stone-100">
  <main class="mx-auto grid max-w-7xl gap-8 px-4 py-8 sm:px-6 lg:grid-cols-[minmax(0,1.35fr)_minmax(22rem,0.65fr)] lg:px-8 lg:py-12">
    <section id="lobby-board" aria-labelledby="lobby-title" class="min-w-0">
      <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.2em] text-[#e06a5b]">Room {lobby.room_code}</p>
          <h1 id="lobby-title" class="mt-2 text-3xl font-semibold tracking-[-0.035em] sm:text-4xl">
            {lobby.title}
          </h1>
          <p class="mt-2 text-sm text-stone-400">{lobby.case_title} · case file v{lobby.case_version}</p>
        </div>
        <span class="border border-white/15 px-3 py-1.5 font-mono text-xs uppercase tracking-[0.16em] text-stone-300">
          {lobby.status}
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

          {#each lobby.players as player, index}
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
            {lobby.players.filter((player) => player.role === "detective").length}/{lobby.max_detectives} detectives
          </span>
        </div>

        <ul class="mt-4 divide-y divide-white/10 border-y border-white/10">
          {#each lobby.players as player}
            <li id={`lobby-player-${player.id}`} class="flex items-center gap-3 py-4">
              <span
                class={`size-2.5 rounded-full ${player.ready ? "bg-emerald-400" : "bg-stone-600"}`}
                aria-hidden="true"
              ></span>
              <span class="min-w-0 flex-1 truncate text-sm text-stone-200">{player.display_name}</span>
              <span class="font-mono text-[11px] uppercase tracking-[0.12em] text-stone-500">{player.role}</span>
              <span class="sr-only">{player.ready ? "Ready" : "Not ready"}</span>
            </li>
          {/each}
        </ul>
      </section>

      <section id="lobby-controls" class="mt-8 border-t border-white/10 pt-6">
        <button
          id="lobby-realtime-pending"
          type="button"
          disabled
          class="w-full border border-white/15 px-4 py-3 text-sm font-semibold text-stone-500"
        >
          Realtime ready controls arrive next
        </button>
      </section>
    </aside>
  </main>
</div>
