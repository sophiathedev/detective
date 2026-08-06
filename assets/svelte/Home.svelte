<script>
  import PaperSheet from "./ui/PaperSheet.svelte"
  import StatusStamp from "./ui/StatusStamp.svelte"
  import WoodFrame from "./ui/WoodFrame.svelte"
  import { initializeI18n } from "./i18n"

  let { signed_in = false, locale = "en" } = $props()
  const { t } = initializeI18n(() => locale)
</script>

<div id="home-svelte" class="relative min-h-[calc(100dvh-3.5rem)] overflow-hidden px-4 py-8 sm:px-6 sm:py-12 lg:px-10">
  <div class="pointer-events-none absolute inset-0 opacity-40" aria-hidden="true">
    <div class="absolute -left-24 top-12 h-px w-[34rem] rotate-[-22deg] bg-[var(--noir-gold-700)]"></div>
    <div class="absolute -right-16 bottom-20 h-px w-[30rem] rotate-[19deg] bg-[var(--noir-gold-700)]"></div>
  </div>

  <WoodFrame
    as="main"
    id="home-case-desk"
    labelledby="home-case-title"
    class="relative mx-auto grid min-h-[calc(100dvh-8.5rem)] max-w-[92rem] overflow-hidden p-3 sm:p-5 lg:grid-cols-[minmax(0,1.4fr)_minmax(22rem,0.7fr)]"
  >
    <section class="relative flex min-h-[34rem] flex-col justify-end overflow-hidden border border-[var(--noir-gold-700)] bg-[var(--noir-ebony-900)] px-6 py-10 sm:px-10 sm:py-14 lg:px-14 lg:py-16">
      <div class="pointer-events-none absolute inset-0" aria-hidden="true">
        <div class="absolute inset-x-0 top-0 h-2/3 bg-[radial-gradient(circle_at_30%_15%,rgba(194,163,95,0.18),transparent_46%)]"></div>
        <div class="absolute -right-16 top-16 h-72 w-72 rotate-12 border border-[var(--noir-gold-700)] opacity-30"></div>
        <div class="absolute right-10 top-28 h-44 w-44 rounded-full border border-[var(--noir-red-500)] opacity-25"></div>
        <div class="absolute bottom-0 left-0 h-48 w-full bg-[linear-gradient(165deg,transparent_35%,rgba(0,0,0,0.72)_36%)]"></div>
      </div>

      <div class="relative max-w-4xl">
        <StatusStamp tone="sealed">{t("Case file 1940-LA")}</StatusStamp>
        <p class="mt-7 font-mono text-xs uppercase tracking-[0.24em] text-[var(--noir-gold-500)]">
          {t("Los Angeles · Midnight detail")}
        </p>
        <h1 id="home-case-title" class="mt-4 max-w-4xl font-serif text-5xl font-semibold leading-[0.93] tracking-[-0.055em] text-[var(--noir-paper-100)] sm:text-7xl lg:text-[6.7rem]">
          {t("Every witness has a story.")}
        </h1>
        <p class="mt-7 max-w-2xl font-serif text-lg leading-8 text-stone-300 sm:text-xl">
          {t("Detectives chase contradictions across the city. The Chisel guards the truth, shapes every testimony, and lets the evidence decide who was listening.")}
        </p>
      </div>
    </section>

    <PaperSheet
      as="aside"
      labelledby="home-brief-title"
      tilt="right"
      class="m-2 flex flex-col justify-between p-6 sm:m-4 sm:p-9 lg:m-6"
    >
      <div>
        <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-[var(--noir-red-700)]">
          {t("Assignment brief")}
        </p>
        <h2 id="home-brief-title" class="mt-3 font-serif text-3xl font-semibold leading-tight">
          {t("Enter the investigation")}
        </h2>
        <div class="mt-5 h-px bg-[var(--noir-paper-500)]"></div>

        <ol class="mt-7 space-y-6" aria-label={t("How a case unfolds")}>
          <li class="grid grid-cols-[2rem_1fr] gap-3">
            <span class="font-mono text-sm font-semibold text-[var(--noir-red-700)]">01</span>
            <div>
              <h3 class="font-serif text-lg font-semibold">{t("Assemble the room")}</h3>
              <p class="mt-1 text-sm leading-6 text-[#5d4936]">{t("One Chisel invites up to four Detectives into a private case.")}</p>
            </div>
          </li>
          <li class="grid grid-cols-[2rem_1fr] gap-3">
            <span class="font-mono text-sm font-semibold text-[var(--noir-red-700)]">02</span>
            <div>
              <h3 class="font-serif text-lg font-semibold">{t("Read the city")}</h3>
              <p class="mt-1 text-sm leading-6 text-[#5d4936]">{t("Move, search, and interrogate while the server enforces every turn.")}</p>
            </div>
          </li>
          <li class="grid grid-cols-[2rem_1fr] gap-3">
            <span class="font-mono text-sm font-semibold text-[var(--noir-red-700)]">03</span>
            <div>
              <h3 class="font-serif text-lg font-semibold">{t("Challenge the lie")}</h3>
              <p class="mt-1 text-sm leading-6 text-[#5d4936]">{t("Commit to a theory before the case closes around you.")}</p>
            </div>
          </li>
        </ol>
      </div>

      <div class="mt-10 border-t border-[var(--noir-paper-500)] pt-6">
        {#if signed_in}
          <a href="/dashboard" class="noir-physical-button inline-flex w-full items-center justify-center px-5 text-sm font-semibold">
            {t("Open case cabinet")}
          </a>
        {:else}
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
            <a href="/users/register" class="noir-physical-button inline-flex items-center justify-center px-5 text-sm font-semibold">
              {t("Open an account")}
            </a>
            <a href="/users/log-in" class="inline-flex min-h-11 items-center justify-center border border-[var(--noir-ink-900)] px-5 text-sm font-semibold text-[var(--noir-ink-900)] transition hover:bg-[var(--noir-ink-900)] hover:text-[var(--noir-paper-100)] focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-red-700)]">
              {t("Log in")}
            </a>
          </div>
        {/if}
        <p class="mt-5 text-xs leading-5 text-[#705a42]">
          {t("Non-commercial fan project. Not affiliated with Van Ryder Games or the original publishers.")}
        </p>
      </div>
    </PaperSheet>
  </WoodFrame>
</div>
