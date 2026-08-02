<script>
  let {
    form = {
      fields: { title: "", case_version_id: "", max_detectives: "", invite_hours: "24" },
      errors: {},
    },
    case_options = [],
    global_error = null,
    created_room = null,
  } = $props()

  let copied = $state(false)

  let fields = $derived(form.fields ?? {})
  let errors = $derived(form.errors ?? {})
  let has_cases = $derived(case_options.length > 0)

  function firstError(field) {
    return errors[field]?.[0]
  }

  async function copyInvite() {
    if (!created_room?.invite_url || !navigator.clipboard) return

    await navigator.clipboard.writeText(created_room.invite_url)
    copied = true
    window.setTimeout(() => (copied = false), 1800)
  }
</script>

<div id="create-game-shell" class="min-h-[100dvh] bg-[#0b0d0e] text-stone-100">
  <header id="create-game-header" class="border-b border-white/10">
    <nav
      class="mx-auto flex h-16 max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8"
      aria-label="Create game navigation"
    >
      <a
        id="create-game-back"
        href="/dashboard"
        class="inline-flex min-h-11 items-center gap-3 rounded-sm text-sm font-medium text-stone-300 transition hover:text-[#ed796b] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#ed796b]"
      >
        <span aria-hidden="true">←</span>
        Dashboard
      </a>
      <span class="font-mono text-xs uppercase tracking-[0.18em] text-stone-400">Room setup</span>
    </nav>
  </header>

  <main class="mx-auto grid max-w-7xl gap-10 px-4 py-10 sm:px-6 lg:grid-cols-[minmax(0,0.88fr)_minmax(30rem,1.12fr)] lg:px-8 lg:py-16">
    <section id="create-game-form-section" aria-labelledby="create-game-title">
      <p class="font-mono text-xs uppercase tracking-[0.2em] text-[#ed796b]">Open a case room</p>
      <h1 id="create-game-title" class="mt-4 text-4xl font-semibold tracking-[-0.04em] text-stone-100 sm:text-5xl">
        Set the table.
      </h1>
      <p class="mt-4 max-w-lg text-base leading-7 text-stone-400">
        Choose a published case and room limits. You will enter the lobby as host after creation.
      </p>

      {#if created_room}
        <section id="created-room" class="mt-8 border border-[#ed796b]/60 bg-[#151819] p-5" aria-labelledby="created-room-title">
          <p class="font-mono text-xs uppercase tracking-[0.18em] text-[#ed796b]">Room {created_room.room_code}</p>
          <h2 id="created-room-title" class="mt-2 text-xl font-semibold text-stone-100">Room created</h2>
          <p class="mt-2 text-sm leading-6 text-stone-400">
            Copy this link now. Raw token disappears after reload and is never stored by the server.
          </p>
          <div class="mt-4 flex gap-2">
            <input
              id="created-room-invite-url"
              aria-label="Invitation URL"
              readonly
              value={created_room.invite_url}
              class="min-w-0 flex-1 border border-white/15 bg-black/20 px-3 py-2 font-mono text-xs text-stone-300 outline-none focus:border-[#ed796b]"
            />
            <button
              id="created-room-copy-invite"
              type="button"
              onclick={copyInvite}
              class="cursor-pointer border border-[#ed796b] px-4 py-2 text-sm font-semibold text-[#ed796b] transition hover:bg-[#ed796b] hover:text-[#0b0d0e]"
            >
              {copied ? "Copied" : "Copy"}
            </button>
          </div>
          <a
            id="created-room-enter-lobby"
            href={created_room.lobby_path}
            class="mt-4 inline-flex min-h-11 items-center justify-center bg-[#ed796b] px-5 py-2.5 text-sm font-semibold text-[#0b0d0e] transition hover:bg-[#ff8b7d]"
          >
            Enter lobby
          </a>
        </section>
      {/if}

      {#if global_error}
        <div
          id="create-game-global-error"
          class="mt-7 border-l-2 border-[#ed796b] bg-[#17191a] px-4 py-3 text-sm leading-6 text-stone-200"
          role="alert"
        >
          {global_error}
        </div>
      {/if}

      {#if !has_cases}
        <div id="case-catalog-empty" class="mt-7 border border-[#ed796b]/50 bg-[#17191a] p-5" role="status">
          <p class="font-medium text-stone-100">No published cases available</p>
          <p class="mt-2 text-sm leading-6 text-stone-400">
            A published case version is required before a room can be created.
          </p>
        </div>
      {/if}

      <form id="create-game-form" class="mt-8 space-y-6" phx-change="validate" phx-submit="save" class:hidden={created_room}>
        <div class="space-y-2">
          <label for="game-title" class="block text-sm font-medium text-stone-200">Room name</label>
          <input
            id="game-title"
            name="game[title]"
            type="text"
            value={fields.title ?? ""}
            required
            minlength="3"
            maxlength="80"
            autocomplete="off"
            placeholder="The midnight dossier"
            aria-invalid={firstError("title") ? "true" : undefined}
            aria-describedby={firstError("title") ? "game-title-error" : "game-title-help"}
            class="min-h-12 w-full border border-stone-600 bg-[#111416] px-4 py-3 text-base text-stone-100 outline-none transition placeholder:text-stone-500 hover:border-stone-500 focus:border-[#ed796b] focus:ring-2 focus:ring-[#ed796b]/25"
          />
          {#if firstError("title")}
            <p id="game-title-error" class="text-sm text-[#ff9b8f]">{firstError("title")}</p>
          {:else}
            <p id="game-title-help" class="text-sm text-stone-400">Visible to every invited player.</p>
          {/if}
        </div>

        <div class="space-y-2">
          <label for="game-case-version-id" class="block text-sm font-medium text-stone-200">Published case</label>
          <select
            id="game-case-version-id"
            name="game[case_version_id]"
            required
            disabled={!has_cases}
            aria-invalid={firstError("case_version_id") ? "true" : undefined}
            aria-describedby={firstError("case_version_id") ? "game-case-version-error" : "game-case-version-help"}
            class="min-h-12 w-full border border-stone-600 bg-[#111416] px-4 py-3 text-base text-stone-100 outline-none transition hover:border-stone-500 focus:border-[#ed796b] focus:ring-2 focus:ring-[#ed796b]/25 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="" selected={(fields.case_version_id ?? "") === ""}>Choose a case</option>
            {#each case_options as option (option.value)}
              <option value={option.value} selected={String(fields.case_version_id ?? "") === String(option.value)}>
                {option.label}
              </option>
            {/each}
          </select>
          {#if firstError("case_version_id")}
            <p id="game-case-version-error" class="text-sm text-[#ff9b8f]">{firstError("case_version_id")}</p>
          {:else}
            <p id="game-case-version-help" class="text-sm text-stone-400">
              Only immutable, published versions can start a game.
            </p>
          {/if}
        </div>

        <div class="grid gap-5 sm:grid-cols-2">
          <div class="space-y-2">
            <label for="game-max-detectives" class="block text-sm font-medium text-stone-200">
              Detective seats
            </label>
            <select
              id="game-max-detectives"
              name="game[max_detectives]"
              required
              aria-invalid={firstError("max_detectives") ? "true" : undefined}
              aria-describedby={firstError("max_detectives") ? "game-max-detectives-error" : "game-max-detectives-help"}
              class="min-h-12 w-full border border-stone-600 bg-[#111416] px-4 py-3 text-base text-stone-100 outline-none transition hover:border-stone-500 focus:border-[#ed796b] focus:ring-2 focus:ring-[#ed796b]/25"
            >
              <option value="" selected={(fields.max_detectives ?? "") === ""}>Choose capacity</option>
              {#each [1, 2, 3, 4] as count}
                <option value={count} selected={String(fields.max_detectives ?? "") === String(count)}>
                  {count} {count === 1 ? "detective" : "detectives"}
                </option>
              {/each}
            </select>
            {#if firstError("max_detectives")}
              <p id="game-max-detectives-error" class="text-sm text-[#ff9b8f]">{firstError("max_detectives")}</p>
            {:else}
              <p id="game-max-detectives-help" class="text-sm text-stone-400">Host seat is separate.</p>
            {/if}
          </div>

          <div class="space-y-2">
            <label for="game-invite-hours" class="block text-sm font-medium text-stone-200">
              Invite expires
            </label>
            <select
              id="game-invite-hours"
              name="game[invite_hours]"
              required
              class="min-h-12 w-full border border-stone-600 bg-[#111416] px-4 py-3 text-base text-stone-100 outline-none transition hover:border-stone-500 focus:border-[#ed796b] focus:ring-2 focus:ring-[#ed796b]/25"
            >
              {#each [["1", "1 hour"], ["6", "6 hours"], ["24", "24 hours"], ["72", "3 days"]] as option}
                <option value={option[0]} selected={String(fields.invite_hours ?? "24") === option[0]}>
                  {option[1]}
                </option>
              {/each}
            </select>
            <p class="text-sm text-stone-400">The link can be revoked earlier from the lobby.</p>
          </div>
        </div>

        <div class="flex flex-col-reverse gap-3 border-t border-white/10 pt-6 sm:flex-row sm:items-center sm:justify-between">
          <a
            id="create-game-cancel"
            href="/dashboard"
            class="inline-flex min-h-11 items-center justify-center px-4 py-2.5 text-sm font-medium text-stone-300 transition hover:bg-white/5 hover:text-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#ed796b]"
          >
            Cancel
          </a>
          <button
            id="create-game-submit"
            type="submit"
            disabled={!has_cases}
            phx-disable-with="Creating game..."
            class="inline-flex min-h-11 cursor-pointer items-center justify-center whitespace-nowrap bg-[#ed796b] px-5 py-2.5 text-sm font-semibold text-[#0b0d0e] transition hover:bg-[#ff8b7d] active:translate-y-px focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#ed796b] disabled:cursor-not-allowed disabled:bg-stone-700 disabled:text-stone-400"
          >
            Create game
          </button>
        </div>
      </form>
    </section>

    <aside
      id="create-game-graphic"
      class="relative min-h-[28rem] overflow-hidden border border-white/10 bg-[#111416] lg:min-h-[44rem]"
      aria-label="Case room preview"
    >
      <svg
        class="absolute inset-0 size-full"
        viewBox="0 0 760 860"
        preserveAspectRatio="xMidYMid slice"
        role="img"
        aria-labelledby="create-game-graphic-title create-game-graphic-description"
      >
        <title id="create-game-graphic-title">A new case room being prepared</title>
        <desc id="create-game-graphic-description">
          An original abstract night city map beneath a blank evidence dossier.
        </desc>
        <defs>
          <pattern id="create-game-grid" width="38" height="38" patternUnits="userSpaceOnUse">
            <path d="M38 0H0v38" fill="none" stroke="#363c3d" stroke-width="1" />
          </pattern>
          <filter id="create-game-shadow" x="-30%" y="-30%" width="160%" height="160%">
            <feDropShadow dx="0" dy="18" stdDeviation="16" flood-color="#050606" flood-opacity="0.65" />
          </filter>
        </defs>

        <rect width="760" height="860" fill="#111416" />
        <rect width="760" height="860" fill="url(#create-game-grid)" opacity="0.5" />
        <g fill="#1b2022" stroke="#4c5354" stroke-width="2">
          <path d="M30 44h174v148H30z" />
          <path d="M240 20h190v112H240z" />
          <path d="M468 48h260v156H468z" />
          <path d="M24 238h130v182H24z" />
          <path d="M190 190h206v162H190z" />
          <path d="M438 246h138v138H438z" />
          <path d="M612 238h120v206H612z" />
          <path d="M32 480h216v142H32z" />
          <path d="M286 414h128v208H286z" />
          <path d="M452 446h270v166H452z" />
          <path d="M24 666h154v158H24z" />
          <path d="M218 658h224v180H218z" />
          <path d="M482 650h246v174H482z" />
        </g>
        <g fill="none" stroke="#747b79">
          <path d="M0 442C178 370 318 392 472 448S638 494 760 430" stroke-width="16" opacity="0.18" />
          <path d="M0 442C178 370 318 392 472 448S638 494 760 430" stroke-width="2" stroke-dasharray="12 12" opacity="0.55" />
          <path d="M430 0v860" stroke-width="8" opacity="0.15" />
        </g>
        <path d="M112 542L248 300 508 376 650 164" fill="none" stroke="#ed796b" stroke-width="2" stroke-dasharray="8 10" />
        <g fill="#111416" stroke="#ed796b" stroke-width="3">
          <circle cx="112" cy="542" r="11" />
          <circle cx="248" cy="300" r="11" />
          <circle cx="508" cy="376" r="11" />
          <circle cx="650" cy="164" r="11" />
        </g>

        <g transform="translate(160 198) rotate(-4)" filter="url(#create-game-shadow)">
          <path d="M0 0h374l54 54v422H0z" fill="#d8d2c7" />
          <path d="M374 0v54h54" fill="#a9a398" />
          <rect x="34" y="34" width="118" height="24" fill="#252829" />
          <path d="M34 82h270M34 106h334M34 130h224" stroke="#898378" stroke-width="3" />
          <rect x="34" y="174" width="150" height="132" fill="none" stroke="#8f897e" stroke-width="2" />
          <path d="M210 184h158M210 208h122M210 232h146M210 256h98M210 280h138" stroke="#8f897e" stroke-width="3" />
          <path d="M34 348h334M34 374h260M34 400h314" stroke="#8f897e" stroke-width="3" />
          <g transform="translate(304 330) rotate(-9)">
            <circle cx="40" cy="40" r="38" fill="none" stroke="#c44f43" stroke-width="5" />
            <path d="M16 40h48M40 16v48" stroke="#c44f43" stroke-width="3" />
          </g>
        </g>
      </svg>

      <div class="absolute inset-x-5 bottom-5 border border-white/15 bg-[#0b0d0e]/95 p-4 sm:inset-x-7 sm:bottom-7">
        <p class="font-mono text-xs uppercase tracking-[0.18em] text-[#ed796b]">Host authority</p>
        <p class="mt-2 text-sm leading-6 text-stone-300">
          Room rules, membership, and invitation expiry remain enforced by the server.
        </p>
      </div>
    </aside>
  </main>
</div>
