<script>
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let { result = null, detectives = [] } = $props()

  let winner = $derived(result?.winner ?? {})
  let winningDetective = $derived(
    detectives.find((detective) => detective.id === winner.player_id) ?? null,
  )
  let verdict = $derived(
    winner.role === "detective"
      ? t("{name} broke the case", { name: winningDetective?.display_name ?? t("A Detective") })
      : t("The Chisel buried the truth"),
  )
  let reason = $derived(
    winner.reason === "case_solved"
      ? t("Solved before the clock expired")
      : winner.reason === "final_guess"
        ? t("Solved by a sealed final guess")
        : t("The Day track expired"),
  )
</script>

<article id="case-closed-result" class="relative overflow-hidden border-2 border-[#71372f] bg-[#dfcda9] p-5 text-[#35291f] sm:p-7" aria-labelledby="case-result-heading">
  <div class="pointer-events-none absolute inset-3 border border-[#9c8264]" aria-hidden="true"></div>
  <header class="relative flex flex-wrap items-start justify-between gap-5 border-b-2 border-[#8d7458] pb-5">
    <div>
      <p class="font-mono text-[9px] uppercase tracking-[0.18em] text-[#8c3f33]">{t("Case closed · solution released")}</p>
      <h3 id="case-result-heading" class="mt-1 font-serif text-3xl font-semibold">{t("The final verdict")}</h3>
      <p class="mt-2 font-serif text-base italic text-[#5a4433]">{reason}</p>
    </div>
    <div class="rotate-[-3deg] border-[3px] border-[#7f342e] px-4 py-3 text-center text-[#7f342e]">
      <p class="font-mono text-[8px] font-bold uppercase tracking-[0.16em]">{t("VERDICT")}</p>
      <p class="mt-1 max-w-48 font-serif text-base font-bold uppercase leading-5">{verdict}</p>
    </div>
  </header>

  {#if result?.solution}
    <dl id="released-solution" class="relative mt-6 grid gap-3 sm:grid-cols-3">
      <div class="border-l-4 border-[#71372f] bg-[#eadbbc] p-4"><dt class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">{t("Suspect")}</dt><dd class="mt-2 font-serif text-xl font-semibold">{result.solution.suspect_name}</dd></div>
      <div class="border-l-4 border-[#71372f] bg-[#eadbbc] p-4"><dt class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">{t("Weapon")}</dt><dd class="mt-2 font-serif text-xl font-semibold">{result.solution.weapon_label}</dd></div>
      <div class="border-l-4 border-[#71372f] bg-[#eadbbc] p-4"><dt class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">{t("Motive")}</dt><dd class="mt-2 font-serif text-xl font-semibold">{result.solution.motive_label}</dd></div>
    </dl>
  {:else}
    <p id="solution-release-error" class="relative mt-6 border border-dashed border-[#8c3f33] p-4 text-sm">{t("The verdict was recorded, but this case version has no releasable solution sheet.")}</p>
  {/if}

  {#if result?.epilogue}
    <section class="relative mt-6 border-y border-[#9c8264] py-5" aria-labelledby="case-epilogue-heading">
      <p class="font-mono text-[9px] uppercase tracking-[0.15em] text-[#8c3f33]">{t("Closing report")}</p>
      <h4 id="case-epilogue-heading" class="sr-only">{t("Epilogue")}</h4>
      <p class="mt-2 max-w-4xl whitespace-pre-line font-serif text-base italic leading-7 text-[#4f3e30]">{result.epilogue}</p>
    </section>
  {/if}

  <footer class="relative mt-6 flex flex-wrap items-center justify-between gap-3">
    <p class="max-w-xl text-xs leading-5 text-[#67513d]">{t("This solution comes from the server-owned case version and is now public to every member of this finished game.")}</p>
    <a id="case-result-dashboard-link" href="/dashboard" class="inline-flex min-h-11 items-center border-2 border-[#392d24] bg-[#392d24] px-4 font-mono text-[9px] font-bold uppercase tracking-[0.12em] text-[#f3e4c6] transition hover:-translate-y-0.5 hover:bg-[#71372f]">{t("Return to case cabinet")}</a>
  </footer>
</article>
