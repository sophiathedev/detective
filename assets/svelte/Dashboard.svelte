<script>
  import StatusStamp from "./ui/StatusStamp.svelte"
  import WoodFrame from "./ui/WoodFrame.svelte"

  let {
    display_name = "Detective",
    games = { waiting: 0, active: 0, finished: 0 },
    dossiers = { waiting: [], active: [], finished: [] },
  } = $props()

  let waiting = $derived(dossiers.waiting ?? [])
  let active = $derived(dossiers.active ?? [])
  let finished = $derived(dossiers.finished ?? [])
  let empty = $derived(waiting.length + active.length + finished.length === 0)
  let buckets = $derived([
    { key: "waiting", title: "Waiting", marker: "Intake", rows: waiting },
    { key: "active", title: "Active", marker: "In field", rows: active },
    { key: "finished", title: "Closed", marker: "Archive", rows: finished },
  ])
</script>

<div id="dashboard-shell" class="min-h-[calc(100dvh-3.5rem)] px-4 py-8 text-stone-100 sm:px-6 sm:py-12 lg:px-10">
  <main id="dashboard-main" class="mx-auto max-w-[92rem]">
    <header class="grid gap-8 border-b border-[var(--noir-gold-700)] pb-8 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
      <div>
        <p class="font-mono text-xs uppercase tracking-[0.22em] text-[var(--noir-gold-500)]">Private case cabinet</p>
        <h1 id="dashboard-title" class="mt-4 font-serif text-5xl font-semibold leading-none tracking-[-0.045em] sm:text-6xl">
          Good evening, {display_name}.
        </h1>
        <p class="mt-4 max-w-2xl text-sm leading-6 text-stone-400">
          Reopen an active investigation, ready a waiting room, or review the files already sealed.
        </p>
      </div>
      <a
        id="dashboard-new-game"
        href="/games/new"
        class="noir-physical-button inline-flex items-center justify-center px-6 text-sm font-semibold"
      >
        Open new case
      </a>
    </header>

    <section id="dashboard-game-summary" class="border-b border-[var(--noir-gold-700)]" aria-labelledby="game-summary-title">
      <h2 id="game-summary-title" class="sr-only">Game summary</h2>
      <dl class="grid sm:grid-cols-3">
        <div id="games-waiting" class="flex items-end justify-between gap-4 py-5 sm:block sm:border-r sm:border-[var(--noir-gold-700)] sm:px-6">
          <dt class="font-mono text-xs uppercase tracking-[0.14em] text-stone-400">Waiting rooms</dt>
          <dd class="font-serif text-4xl text-[var(--noir-paper-100)] sm:mt-2">{games.waiting ?? 0}</dd>
        </div>
        <div id="games-active" class="flex items-end justify-between gap-4 border-t border-[var(--noir-gold-700)] py-5 sm:block sm:border-r sm:border-t-0 sm:px-6">
          <dt class="font-mono text-xs uppercase tracking-[0.14em] text-stone-400">Active cases</dt>
          <dd class="font-serif text-4xl text-[var(--noir-paper-100)] sm:mt-2">{games.active ?? 0}</dd>
        </div>
        <div id="games-finished" class="flex items-end justify-between gap-4 border-t border-[var(--noir-gold-700)] py-5 sm:block sm:border-t-0 sm:px-6">
          <dt class="font-mono text-xs uppercase tracking-[0.14em] text-stone-400">Closed cases</dt>
          <dd class="font-serif text-4xl text-[var(--noir-paper-100)] sm:mt-2">{games.finished ?? 0}</dd>
        </div>
      </dl>
    </section>

    <WoodFrame
      as="section"
      id="dashboard-case-cabinet"
      labelledby="case-cabinet-title"
      class="mt-8 overflow-hidden p-3 sm:p-5"
    >
      <h2 id="case-cabinet-title" class="sr-only">Investigation case cabinet</h2>

      {#if empty}
        <section id="dashboard-empty-state" class="noir-paper-sheet grid min-h-64 place-items-center p-8 text-center" aria-labelledby="dashboard-empty-title">
          <div>
            <StatusStamp tone="neutral">Cabinet empty</StatusStamp>
            <h3 id="dashboard-empty-title" class="mt-5 font-serif text-3xl font-semibold">No investigations yet</h3>
            <p class="mx-auto mt-3 max-w-lg text-sm leading-6 text-[#66513c]">
              Open a case, select a published file, then invite the Detectives you trust.
            </p>
            <a
              id="dashboard-empty-create-game"
              href="/games/new"
              class="noir-physical-button mt-7 inline-flex items-center justify-center px-5 text-sm font-semibold"
            >
              Open first case
            </a>
          </div>
        </section>
      {:else}
        <div class="grid gap-3 lg:grid-cols-3">
          {#each buckets as bucket (bucket.key)}
            <section class="min-w-0 border border-[var(--noir-gold-700)] bg-[var(--noir-ebony-900)] p-3" aria-labelledby={`dashboard-${bucket.key}-title`}>
              <header class="flex items-center justify-between gap-3 border-b border-[var(--noir-gold-700)] px-2 pb-3">
                <h3 id={`dashboard-${bucket.key}-title`} class="font-serif text-2xl font-semibold">{bucket.title}</h3>
                <span class="font-mono text-[0.6rem] uppercase tracking-[0.15em] text-[var(--noir-gold-500)]">{bucket.marker}</span>
              </header>

              <div class="mt-3 space-y-3">
                {#each bucket.rows as game (game.id)}
                  <article class="noir-paper-sheet overflow-hidden">
                    <a
                      href={game.path}
                      aria-label={`Open ${game.title}`}
                      class="group block min-h-52 p-5 transition hover:-translate-y-0.5 focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-focus)]"
                    >
                      <div class="flex items-start justify-between gap-4">
                        <StatusStamp tone={game.status === "paused" ? "danger" : "neutral"}>
                          {game.phase}
                        </StatusStamp>
                        <span class="font-mono text-xs font-semibold tracking-[0.12em] text-[var(--noir-red-700)]">
                          {game.room_code}
                        </span>
                      </div>
                      <h4 class="mt-5 font-serif text-2xl font-semibold leading-tight text-[var(--noir-ink-900)] group-hover:text-[var(--noir-red-700)]">
                        {game.title}
                      </h4>
                      <p class="mt-2 text-sm leading-6 text-[#66513c]">{game.case_title}</p>
                      <dl class="mt-6 grid grid-cols-2 gap-3 border-t border-[var(--noir-paper-500)] pt-4 font-mono text-[0.65rem] uppercase tracking-[0.09em]">
                        <div>
                          <dt class="text-[#806b50]">Role</dt>
                          <dd class="mt-1 font-semibold text-[var(--noir-ink-900)]">{game.role}</dd>
                        </div>
                        <div class="text-right">
                          <dt class="text-[#806b50]">Detectives</dt>
                          <dd class="mt-1 font-semibold text-[var(--noir-ink-900)]">{game.detective_count}/{game.max_detectives}</dd>
                        </div>
                      </dl>
                    </a>
                  </article>
                {:else}
                  <p class="px-2 py-5 font-serif text-sm italic text-stone-500">No files in this drawer.</p>
                {/each}
              </div>
            </section>
          {/each}
        </div>
      {/if}
    </WoodFrame>
  </main>
</div>
