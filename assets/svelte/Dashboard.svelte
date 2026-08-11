<script>
  import StatusStamp from "./ui/StatusStamp.svelte"
  import WoodFrame from "./ui/WoodFrame.svelte"
  import { initializeI18n } from "./i18n"

  let {
    display_name = "Detective",
    games = { waiting: 0, active: 0, finished: 0 },
    dossiers = { waiting: [], active: [], finished: [] },
    rematch_room = null,
    rematch_error = null,
    locale = "en",
  } = $props()
  const { t } = initializeI18n(() => locale)

  let waiting = $derived(dossiers.waiting ?? [])
  let active = $derived(dossiers.active ?? [])
  let finished = $derived(dossiers.finished ?? [])
  let empty = $derived(waiting.length + active.length + finished.length === 0)
  let buckets = $derived([
    { key: "waiting", title: t("Waiting"), marker: t("Intake"), rows: waiting },
    { key: "active", title: t("Active"), marker: t("In field"), rows: active },
    { key: "finished", title: t("Closed"), marker: t("Archive"), rows: finished },
  ])
  let rematchCopied = $state(false)

  async function copyRematchInvite() {
    if (!rematch_room?.invite_url || !navigator.clipboard) return

    await navigator.clipboard.writeText(rematch_room.invite_url)
    rematchCopied = true
    window.setTimeout(() => (rematchCopied = false), 1800)
  }

  function closedDate(value) {
    if (!value) return t("Closure pending")

    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return t("Closure pending")

    return new Intl.DateTimeFormat(locale === "vi" ? "vi-VN" : "en-US", {
      dateStyle: "medium",
    }).format(date)
  }

  function duration(game) {
    if (!game.started_at || !game.finished_at) return t("Duration unavailable")

    const seconds = Math.max(
      0,
      Math.round((new Date(game.finished_at).getTime() - new Date(game.started_at).getTime()) / 1000),
    )

    if (!Number.isFinite(seconds)) return t("Duration unavailable")

    const hours = Math.floor(seconds / 3600)
    const minutes = Math.max(1, Math.floor((seconds % 3600) / 60))
    return hours > 0 ? t("{hours}h {minutes}m", { hours, minutes }) : t("{minutes}m", { minutes })
  }

  function finishReason(reason) {
    const labels = {
      case_solved: "Case solved",
      final_guess: "Final deduction",
      time_expired: "Trail went cold",
      abandoned: "Investigation abandoned",
    }

    return t(labels[reason] ?? "Result recorded")
  }
</script>

<div id="dashboard-shell" class="min-h-[calc(100dvh-3.5rem)] px-4 py-8 text-stone-100 sm:px-6 sm:py-12 lg:px-10">
  <div id="dashboard-main" class="mx-auto max-w-[92rem]">
    <header class="grid gap-8 border-b border-[var(--noir-gold-700)] pb-8 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
      <div>
        <p class="font-mono text-xs uppercase tracking-[0.22em] text-[var(--noir-gold-500)]">{t("Private case cabinet")}</p>
        <h1 id="dashboard-title" class="mt-4 font-serif text-5xl font-semibold leading-none tracking-[-0.045em] sm:text-6xl">
          {t("Good evening, {name}.", { name: display_name })}
        </h1>
        <p class="mt-4 max-w-2xl text-sm leading-6 text-stone-400">
          {t("Reopen an active investigation, ready a waiting room, or review the files already sealed.")}
        </p>
      </div>
      <a
        id="dashboard-new-game"
        href="/games/new"
        class="noir-physical-button inline-flex items-center justify-center px-6 text-sm font-semibold"
      >
        {t("Open new case")}
      </a>
    </header>

    <section id="dashboard-game-summary" class="border-b border-[var(--noir-gold-700)]" aria-labelledby="game-summary-title">
      <h2 id="game-summary-title" class="sr-only">{t("Game summary")}</h2>
      <dl class="grid sm:grid-cols-3">
        <div id="games-waiting" class="flex items-end justify-between gap-4 py-5 sm:block sm:border-r sm:border-[var(--noir-gold-700)] sm:px-6">
          <dt class="font-mono text-xs uppercase tracking-[0.14em] text-stone-400">{t("Waiting rooms")}</dt>
          <dd class="font-serif text-4xl text-[var(--noir-paper-100)] sm:mt-2">{games.waiting ?? 0}</dd>
        </div>
        <div id="games-active" class="flex items-end justify-between gap-4 border-t border-[var(--noir-gold-700)] py-5 sm:block sm:border-r sm:border-t-0 sm:px-6">
          <dt class="font-mono text-xs uppercase tracking-[0.14em] text-stone-400">{t("Active cases")}</dt>
          <dd class="font-serif text-4xl text-[var(--noir-paper-100)] sm:mt-2">{games.active ?? 0}</dd>
        </div>
        <div id="games-finished" class="flex items-end justify-between gap-4 border-t border-[var(--noir-gold-700)] py-5 sm:block sm:border-t-0 sm:px-6">
          <dt class="font-mono text-xs uppercase tracking-[0.14em] text-stone-400">{t("Closed cases")}</dt>
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
      <h2 id="case-cabinet-title" class="sr-only">{t("Investigation case cabinet")}</h2>

      {#if rematch_error}
        <div id="dashboard-rematch-error" class="mb-3 border border-[var(--noir-red-500)] bg-[#2a1714] px-4 py-3 text-sm text-[#f0c2b7]" role="alert">
          {t(rematch_error)}
        </div>
      {/if}

      {#if empty}
        <section id="dashboard-empty-state" class="noir-paper-sheet grid min-h-64 place-items-center p-8 text-center" aria-labelledby="dashboard-empty-title">
          <div>
            <StatusStamp tone="neutral">{t("Cabinet empty")}</StatusStamp>
            <h3 id="dashboard-empty-title" class="mt-5 font-serif text-3xl font-semibold">{t("No investigations yet")}</h3>
            <p class="mx-auto mt-3 max-w-lg text-sm leading-6 text-[#66513c]">
              {t("Open a case, select a published file, then invite the Detectives you trust.")}
            </p>
            <a
              id="dashboard-empty-create-game"
              href="/games/new"
              class="noir-physical-button mt-7 inline-flex items-center justify-center px-5 text-sm font-semibold"
            >
              {t("Open first case")}
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
                      aria-label={t("Open {title}", { title: game.title })}
                      class="group block min-h-52 p-5 transition hover:-translate-y-0.5 focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-focus)]"
                    >
                      <div class="flex items-start justify-between gap-4">
                        <StatusStamp tone={game.status === "paused" ? "danger" : "neutral"}>
                          {t(game.phase)}
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
                          <dt class="text-[#806b50]">{t("Role")}</dt>
                          <dd class="mt-1 font-semibold text-[var(--noir-ink-900)]">{t(game.role)}</dd>
                        </div>
                        <div class="text-right">
                          <dt class="text-[#806b50]">{t("Detectives")}</dt>
                          <dd class="mt-1 font-semibold text-[var(--noir-ink-900)]">{game.detective_count}/{game.max_detectives}</dd>
                        </div>
                      </dl>
                      {#if game.status === "finished"}
                        <div
                          id={`dossier-result-${game.id}`}
                          class="mt-4 border-t border-[#9b8465] pt-4"
                        >
                          <div class="flex items-start justify-between gap-3">
                            <div>
                              <p class="font-serif text-lg font-semibold text-[var(--noir-ink-900)]">
                                {game.won ? t("Case closed in your favor") : t("The truth escaped your theory")}
                              </p>
                              <p class="mt-1 font-mono text-[0.6rem] uppercase tracking-[0.1em] text-[#725f48]">
                                {finishReason(game.finish_reason)} · {t(game.winner_role ?? "Result recorded")}
                              </p>
                            </div>
                            <StatusStamp tone={game.won ? "ready" : "danger"}>
                              {game.won ? t("Won") : t("Lost")}
                            </StatusStamp>
                          </div>
                          <p class="mt-3 font-mono text-[0.58rem] uppercase tracking-[0.08em] text-[#806b50]">
                            {t("Closed {date} · {duration}", {
                              date: closedDate(game.finished_at),
                              duration: duration(game),
                            })}
                          </p>
                        </div>
                      {/if}
                    </a>
                    {#if game.status === "finished"}
                      <div class="grid gap-2 border-t border-[#9b8465] bg-[#c9b995] p-3" class:grid-cols-2={game.role === "chisel"}>
                        <a
                          id={`dossier-replay-${game.id}`}
                          href={game.replay_path}
                          class="noir-physical-button inline-flex items-center justify-center px-4 text-sm font-semibold"
                        >
                          {t("Review timeline")}
                        </a>
                        {#if game.role === "chisel"}
                          <button
                            id={`dossier-rematch-${game.id}`}
                            type="button"
                            phx-click="rematch"
                            phx-value-id={game.id}
                            phx-disable-with={t("Opening rematch…")}
                            class="noir-physical-button w-full px-4 text-sm font-semibold"
                          >
                            {t("Open rematch")}
                          </button>
                        {/if}
                      </div>
                    {/if}
                  </article>
                {:else}
                  <p class="px-2 py-5 font-serif text-sm italic text-stone-500">{t("No files in this drawer.")}</p>
                {/each}
              </div>
            </section>
          {/each}
        </div>
      {/if}
    </WoodFrame>

    {#if rematch_room}
      <div
        id="rematch-created-overlay"
        class="fixed inset-0 z-50 grid place-items-center bg-black/75 p-4 backdrop-blur-sm"
        role="dialog"
        aria-modal="true"
        aria-labelledby="rematch-created-title"
      >
        <WoodFrame as="section" class="w-full max-w-xl p-3 sm:p-4">
          <section class="noir-paper-sheet p-6 sm:p-8">
            <div class="flex items-start justify-between gap-4">
              <StatusStamp tone="ready">{t("Room {code}", { code: rematch_room.room_code })}</StatusStamp>
              <button
                id="dismiss-rematch"
                type="button"
                phx-click="dismiss_rematch"
                class="font-mono text-xs uppercase tracking-[0.12em] text-[#6f5a42] hover:text-[var(--noir-red-700)]"
              >
                {t("Close")}
              </button>
            </div>
            <h2 id="rematch-created-title" class="mt-5 font-serif text-3xl font-semibold text-[var(--noir-ink-900)]">
              {rematch_room.duplicate ? t("Rematch already on file") : t("Fresh rematch sealed")}
            </h2>
            <p class="mt-3 text-sm leading-6 text-[#66513c]">
              {rematch_room.invite_url
                ? t("A fresh invitation was issued. Copy it before leaving this page.")
                : t("This rematch was already created. Enter it to review or regenerate its invitation.")}
            </p>

            {#if rematch_room.invite_url}
              <div class="mt-5 grid gap-2">
                <input
                  id="rematch-invite-url"
                  aria-label={t("Invitation URL")}
                  readonly
                  value={rematch_room.invite_url}
                  class="noir-field px-3 py-2 font-mono text-xs"
                />
                <button
                  id="copy-rematch-invite"
                  type="button"
                  onclick={copyRematchInvite}
                  class="noir-physical-button px-4 text-sm font-semibold"
                >
                  {rematchCopied ? t("Copied") : t("Copy invitation")}
                </button>
              </div>
            {/if}

            <a
              id="enter-rematch"
              href={rematch_room.path}
              class="mt-5 inline-flex min-h-12 w-full items-center justify-center bg-[var(--noir-red-700)] px-5 text-sm font-semibold text-[var(--noir-paper-100)] transition hover:bg-[var(--noir-red-500)] focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-focus)]"
            >
              {t("Enter rematch")}
            </a>
          </section>
        </WoodFrame>
      </div>
    {/if}
  </div>
</div>
