<script>
  let {
    display_name = "Detective",
    games = { waiting: 0, active: 0, finished: 0 },
  } = $props()
</script>

<div id="dashboard-shell" class="min-h-[100dvh] bg-[#0b0d0e] text-stone-100">
  <main id="dashboard-main" class="mx-auto max-w-7xl px-4 pb-12 pt-8 sm:px-6 sm:pt-12 lg:px-8 lg:pb-16">
    <section
      id="dashboard-overview"
      class="grid items-stretch gap-8 lg:grid-cols-[minmax(0,0.78fr)_minmax(32rem,1.22fr)] lg:gap-12"
      aria-labelledby="dashboard-title"
    >
      <div class="flex flex-col justify-between py-2 lg:py-8">
        <div>
          <p class="font-mono text-xs uppercase tracking-[0.2em] text-[#e06a5b]">Private case desk</p>
          <h1
            id="dashboard-title"
            class="mt-5 max-w-xl text-4xl font-semibold leading-[0.98] tracking-[-0.045em] text-stone-100 sm:text-5xl lg:text-6xl"
          >
            Good evening,<br />{display_name}.
          </h1>
          <p class="mt-6 max-w-md text-base leading-7 text-stone-400">
            Your desk is clear. Open an investigation, invite your team, and keep every clue in one secure room.
          </p>
        </div>

        <div class="mt-9 flex flex-wrap items-center gap-4">
          <a
            id="dashboard-new-game"
            href="/games/new"
            class="inline-flex min-h-11 items-center justify-center whitespace-nowrap bg-[#e06a5b] px-5 py-3 text-sm font-semibold text-[#0b0d0e] transition hover:bg-[#ef7a6a] active:translate-y-px focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#e06a5b]"
          >
            Create game
          </a>
          <span class="text-sm text-stone-400">Invite links appear after room creation.</span>
        </div>
      </div>

      <div
        id="dashboard-city-graphic"
        class="relative min-h-[22rem] overflow-hidden border border-white/10 bg-[#111416] sm:min-h-[30rem] lg:min-h-[34rem]"
      >
        <svg
          id="dashboard-city-scene"
          class="absolute inset-0 size-full"
          viewBox="0 0 960 620"
          preserveAspectRatio="xMidYMid slice"
          role="img"
          aria-labelledby="dashboard-city-title dashboard-city-description"
        >
          <title id="dashboard-city-title">An empty investigator's city desk</title>
          <desc id="dashboard-city-description">
            An original abstract city map with an unopened case file and evidence markers.
          </desc>

          <defs>
            <pattern id="dashboard-map-grid" width="32" height="32" patternUnits="userSpaceOnUse">
              <path d="M 32 0 L 0 0 0 32" fill="none" stroke="#34393a" stroke-width="1" />
            </pattern>
            <filter id="dashboard-paper-shadow" x="-30%" y="-30%" width="160%" height="160%">
              <feDropShadow dx="0" dy="14" stdDeviation="12" flood-color="#050606" flood-opacity="0.5" />
            </filter>
          </defs>

          <rect width="960" height="620" fill="#111416" />
          <rect width="960" height="620" fill="url(#dashboard-map-grid)" opacity="0.55" />

          <g fill="#1b2022" stroke="#495052" stroke-width="2">
            <path d="M34 62h178v104H34z" />
            <path d="M244 34h164v98H244z" />
            <path d="M438 58h208v126H438z" />
            <path d="M676 36h246v86H676z" />
            <path d="M52 204h126v144H52z" />
            <path d="M208 174h194v110H208z" />
            <path d="M432 222h126v112H432z" />
            <path d="M592 180h156v170H592z" />
            <path d="M782 160h142v118H782z" />
            <path d="M32 390h206v166H32z" />
            <path d="M270 342h146v108H270z" />
            <path d="M446 382h184v178H446z" />
            <path d="M662 392h118v144H662z" />
            <path d="M812 326h112v224H812z" />
          </g>

          <g fill="none" stroke="#777c79" stroke-linecap="square">
            <path d="M0 366C184 310 336 334 494 370S770 416 960 306" stroke-width="18" opacity="0.2" />
            <path d="M0 366C184 310 336 334 494 370S770 416 960 306" stroke-width="2" stroke-dasharray="14 12" opacity="0.6" />
            <path d="M416 0v620" stroke-width="7" opacity="0.16" />
            <path d="M416 0v620" stroke-width="1" stroke-dasharray="9 10" opacity="0.55" />
          </g>

          <g fill="none" stroke="#cf5547" stroke-width="2">
            <path d="M150 262L338 98 518 278 708 102" stroke-dasharray="7 9" opacity="0.9" />
            <circle cx="150" cy="262" r="10" fill="#111416" />
            <circle cx="338" cy="98" r="10" fill="#111416" />
            <circle cx="518" cy="278" r="10" fill="#111416" />
            <circle cx="708" cy="102" r="10" fill="#111416" />
          </g>

          <g transform="translate(520 252) rotate(-5)" filter="url(#dashboard-paper-shadow)">
            <path d="M0 0h292l44 44v258H0z" fill="#d9d3c7" />
            <path d="M292 0v44h44" fill="#aaa398" />
            <path d="M30 34h160" stroke="#242728" stroke-width="8" />
            <path d="M30 58h116" stroke="#777267" stroke-width="3" />
            <path d="M30 96h266M30 118h266M30 140h186" stroke="#8f897d" stroke-width="2" />
            <rect x="30" y="178" width="114" height="76" fill="none" stroke="#928b7e" stroke-width="2" />
            <path d="M166 184h126M166 204h102M166 224h116M166 244h72" stroke="#928b7e" stroke-width="2" />
            <g transform="translate(226 236) rotate(-8)">
              <circle cx="36" cy="36" r="34" fill="none" stroke="#b7463a" stroke-width="4" />
              <path d="M14 36h44M36 14v44" stroke="#b7463a" stroke-width="3" opacity="0.8" />
            </g>
          </g>

          <g transform="translate(54 478)">
            <rect width="276" height="82" fill="#0b0d0e" stroke="#666b69" />
            <text x="20" y="32" fill="#d9d3c7" font-family="ui-monospace, monospace" font-size="13" letter-spacing="3">
              CASE DESK
            </text>
            <text x="20" y="59" fill="#cf5547" font-family="ui-monospace, monospace" font-size="17" font-weight="700">
              NO OPEN FILES
            </text>
          </g>
        </svg>

        <div
          class="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-[#111416] to-transparent"
          aria-hidden="true"
        ></div>
      </div>
    </section>

    <section id="dashboard-game-summary" class="mt-10 border-y border-white/10" aria-labelledby="game-summary-title">
      <h2 id="game-summary-title" class="sr-only">Game summary</h2>
      <dl class="grid sm:grid-cols-3">
        <div id="games-waiting" class="flex items-end justify-between gap-4 py-6 sm:block sm:border-r sm:border-white/10 sm:px-6">
          <dt class="text-sm text-stone-400">Waiting rooms</dt>
          <dd class="font-mono text-3xl font-medium text-stone-200 sm:mt-3">{games.waiting ?? 0}</dd>
        </div>
        <div id="games-active" class="flex items-end justify-between gap-4 border-t border-white/10 py-6 sm:block sm:border-r sm:border-t-0 sm:border-white/10 sm:px-6">
          <dt class="text-sm text-stone-400">Active cases</dt>
          <dd class="font-mono text-3xl font-medium text-stone-200 sm:mt-3">{games.active ?? 0}</dd>
        </div>
        <div id="games-finished" class="flex items-end justify-between gap-4 border-t border-white/10 py-6 sm:block sm:border-t-0 sm:px-6">
          <dt class="text-sm text-stone-400">Closed cases</dt>
          <dd class="font-mono text-3xl font-medium text-stone-200 sm:mt-3">{games.finished ?? 0}</dd>
        </div>
      </dl>
    </section>

    <section
      id="dashboard-empty-state"
      class="grid gap-6 py-10 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"
      aria-labelledby="dashboard-empty-title"
    >
      <div>
        <h2 id="dashboard-empty-title" class="text-xl font-semibold tracking-tight text-stone-200">
          No investigations yet
        </h2>
        <p class="mt-2 max-w-xl text-sm leading-6 text-stone-400">
          Games you host or join will appear here with role, room status, and the next action.
        </p>
      </div>
      <a
        id="dashboard-empty-create-game"
        href="/games/new"
        class="inline-flex min-h-11 items-center justify-center whitespace-nowrap border border-stone-600 px-4 py-2.5 text-sm font-medium text-stone-200 transition hover:border-[#cf5547] hover:text-[#e06a5b] active:translate-y-px focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#e06a5b]"
      >
        Open first case
      </a>
    </section>
  </main>
</div>
