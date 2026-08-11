<script>
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let { result = null, detectives = [] } = $props()

  let winner = $derived(result?.winner ?? {})
  let reports = $derived(result?.detectives ?? [])
  let investigation = $derived(result?.investigation ?? {})
  let winningDetective = $derived(
    detectives.find((detective) => detective.id === winner.player_id) ?? null,
  )
  let verdict = $derived(
    winner.reason === "chisel_forfeit"
      ? t("The Detectives forced a concession")
      : winner.role === "detective"
      ? t("{name} broke the case", { name: winningDetective?.display_name ?? t("A Detective") })
      : t("The Chisel buried the truth"),
  )
  let reason = $derived(
    winner.reason === "case_solved"
      ? t("Solved before the clock expired")
      : winner.reason === "final_guess"
        ? t("Solved by a sealed final guess")
        : winner.reason === "chisel_forfeit"
          ? t("The Chisel conceded and released the solution")
          : t("The Day track expired"),
  )

  function filedDeduction(report) {
    return report.final_guess ?? report.solve_attempt ?? null
  }

  function filingLabel(report) {
    return report.final_guess ? t("Final sealed guess") : t("Solve accusation")
  }

  function priorSolveCount(report) {
    const count = report.solve_attempt?.correct_count
    return Number.isInteger(count) ? count : null
  }

  function activityItems(report) {
    return [
      [t("Moves"), report.activity?.moves ?? 0],
      [t("Searches"), report.activity?.searches ?? 0],
      [t("Questions"), report.activity?.interrogations ?? 0],
      [t("Challenges"), report.activity?.challenges ?? 0],
    ]
  }

  let investigationItems = $derived([
    [t("Days worked"), investigation.days_elapsed ?? 0],
    [t("Moves"), investigation.moves ?? 0],
    [t("Searches"), investigation.searches ?? 0],
    [t("Questions"), investigation.interrogations ?? 0],
    [t("Challenges"), investigation.challenges ?? 0],
    [t("Public leads"), investigation.public_leads ?? 0],
  ])
</script>

<article id="case-closed-result" class="relative overflow-hidden border-2 border-[#71372f] bg-[#dfcda9] p-5 text-[#35291f] shadow-[inset_0_0_36px_rgba(74,45,25,0.16)] sm:p-7" aria-labelledby="case-result-heading">
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

  <section id="investigation-debrief" class="relative mt-7" aria-labelledby="investigation-debrief-heading">
    <div class="flex flex-wrap items-end justify-between gap-3 border-b border-[#8f765a] pb-3">
      <div>
        <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">{t("Post-case debrief")}</p>
        <h4 id="investigation-debrief-heading" class="mt-1 font-serif text-2xl font-semibold">{t("Investigation ledger")}</h4>
      </div>
      <p class="max-w-md text-right text-xs leading-5 text-[#67513d]">
        {t("A server-audited record of the field work filed before the case was closed.")}
      </p>
    </div>

    <dl class="mt-4 grid grid-cols-2 border-l border-t border-[#a58b6d] sm:grid-cols-3 lg:grid-cols-6">
      {#each investigationItems as [label, value] (label)}
        <div class="border-b border-r border-[#a58b6d] bg-[#eadbbc]/70 px-3 py-3 text-center">
          <dt class="font-mono text-[8px] uppercase tracking-[0.12em] text-[#725e48]">{label}</dt>
          <dd class="mt-1 font-serif text-2xl font-semibold tabular-nums">{value}</dd>
        </div>
      {/each}
    </dl>
    <div class="mt-2 flex flex-wrap justify-end gap-x-4 gap-y-1 text-right font-mono text-[8px] uppercase tracking-[0.12em] text-[#725e48]">
      <p>{t("Challenges sustained · {succeeded}/{total}", { succeeded: investigation.successful_challenges ?? 0, total: investigation.challenges ?? 0 })}</p>
      <p>{t("Evidence taken · {count}", { count: investigation.evidence_taken ?? 0 })}</p>
    </div>
  </section>

  <section id="detective-deductions" class="relative mt-8" aria-labelledby="detective-deductions-heading">
    <div class="border-b-2 border-[#8f765a] pb-3">
      <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">{t("Sealed statements · released")}</p>
      <h4 id="detective-deductions-heading" class="mt-1 font-serif text-2xl font-semibold">{t("Detective deductions")}</h4>
      <p class="mt-1 max-w-3xl text-sm leading-6 text-[#67513d]">
        {t("Every theory below was resolved by the server against the locked case version after play ended.")}
      </p>
    </div>

    {#if reports.length > 0}
      <div class="mt-5 grid gap-4 lg:grid-cols-2">
        {#each reports as report (report.player_id)}
          {@const deduction = filedDeduction(report)}
          {@const earlierSolveCount = priorSolveCount(report)}
          <article
            id={`detective-debrief-${report.player_id}`}
            class={[
              "relative overflow-hidden border bg-[#eadbbc] p-4 shadow-[3px_4px_0_rgba(76,54,35,0.16)]",
              report.won ? "border-2 border-[#7f342e]" : "border-[#9c8264]",
            ].join(" ")}
          >
            <div class="pointer-events-none absolute -right-5 -top-5 size-20 rotate-12 rounded-full border border-[#a68a69]/40" aria-hidden="true"></div>
            <header class="relative flex items-start justify-between gap-3 border-b border-dashed border-[#9c8264] pb-3">
              <div>
                <p class="font-mono text-[8px] uppercase tracking-[0.14em] text-[#80694f]">{t("Detective {seat}", { seat: report.seat ?? "—" })}</p>
                <h5 class="mt-1 font-serif text-xl font-semibold">{report.display_name}</h5>
              </div>
              {#if report.won}
                <span class="rotate-[-3deg] border-2 border-[#7f342e] px-2 py-1 font-mono text-[8px] font-bold uppercase tracking-[0.12em] text-[#7f342e]">{t("WINNING FILE")}</span>
              {/if}
            </header>

            {#if deduction}
              <div class="relative mt-4 flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p class="font-mono text-[8px] uppercase tracking-[0.13em] text-[#80694f]">{filingLabel(report)}</p>
                  <p class="mt-1 font-serif text-sm italic text-[#5a4433]">
                    {t("{count} / 3 links matched the truth", { count: deduction.correct_count })}
                  </p>
                </div>
                <div class="flex gap-1.5" aria-label={t("{count} of 3 correct", { count: deduction.correct_count })}>
                  {#each [1, 2, 3] as marker}
                    <span
                      class={[
                        "grid size-8 place-items-center border font-mono text-xs font-bold",
                        marker <= deduction.correct_count
                          ? "border-[#7f342e] bg-[#7f342e] text-[#f3e4c6]"
                          : "border-[#9c8264] text-[#9c8264]",
                      ].join(" ")}
                      aria-hidden="true"
                    >{marker}</span>
                  {/each}
                </div>
              </div>

              <dl class="relative mt-4 grid gap-2 sm:grid-cols-3">
                <div class="border-l-2 border-[#80694f] pl-3"><dt class="font-mono text-[8px] uppercase tracking-[0.1em] text-[#80694f]">{t("Suspect named")}</dt><dd class="mt-1 font-serif font-semibold">{deduction.suspect_name}</dd></div>
                <div class="border-l-2 border-[#80694f] pl-3"><dt class="font-mono text-[8px] uppercase tracking-[0.1em] text-[#80694f]">{t("Weapon named")}</dt><dd class="mt-1 font-serif font-semibold">{deduction.weapon_label}</dd></div>
                <div class="border-l-2 border-[#80694f] pl-3"><dt class="font-mono text-[8px] uppercase tracking-[0.1em] text-[#80694f]">{t("Motive alleged")}</dt><dd class="mt-1 font-serif font-semibold">{deduction.motive_label}</dd></div>
              </dl>

              {#if report.final_guess && earlierSolveCount !== null}
                <p class="relative mt-3 border-t border-dashed border-[#aa9275] pt-2 text-xs italic text-[#67513d]">
                  {t("Earlier Solve attempt · {count}/3 correct", { count: earlierSolveCount })}
                </p>
              {/if}
            {:else}
              <p class="relative mt-4 border border-dashed border-[#9c8264] px-3 py-4 font-serif text-sm italic text-[#67513d]">
                {t("No valid deduction was filed in the recovered case record.")}
              </p>
            {/if}

            <div class="relative mt-4 border-t border-[#9c8264] pt-3">
              <p class="font-mono text-[8px] uppercase tracking-[0.13em] text-[#80694f]">{t("Field record")}</p>
              <dl class="mt-2 grid grid-cols-4 gap-2">
                {#each activityItems(report) as [label, value] (label)}
                  <div><dt class="truncate text-[9px] text-[#725e48]">{label}</dt><dd class="font-mono text-sm font-bold tabular-nums">{value}</dd></div>
                {/each}
              </dl>
            </div>
          </article>
        {/each}
      </div>
    {:else}
      <p id="detective-debrief-empty" class="mt-4 border border-dashed border-[#9c8264] p-4 text-sm text-[#67513d]">
        {t("No Detective debrief survived in this recovered case record.")}
      </p>
    {/if}
  </section>

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
