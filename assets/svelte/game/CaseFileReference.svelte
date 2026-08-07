<script>
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let {
    briefing = null,
    specialRules = [],
    day = 1,
    daysRemaining = 0,
    role = "detective",
  } = $props()
</script>

<article id="case-file-reference" class="grid gap-5 text-[#392d24]" aria-labelledby="case-file-heading">
  <header class="relative overflow-hidden border-2 border-[#76543d] bg-[#d9c8a8] p-5 sm:p-6">
    <div class="absolute right-[-1.4rem] top-3 rotate-[11deg] border-2 border-[#8c3f33] px-6 py-2 font-mono text-[9px] font-bold uppercase tracking-[0.18em] text-[#8c3f33] opacity-80" aria-hidden="true">{t("OPEN FILE")}</div>
    <p class="font-mono text-[9px] uppercase tracking-[0.18em] text-[#8c3f33]">{t("Case intake · public copy")}</p>
    <h3 id="case-file-heading" class="mt-1 max-w-2xl font-serif text-2xl font-semibold sm:text-3xl">{t("Briefing for the investigation")}</h3>
    <p id="case-public-briefing" class="mt-5 max-w-3xl whitespace-pre-line border-l-4 border-[#75503b] pl-4 font-serif text-base leading-7 text-[#4d3b2d]">
      {briefing || t("No public briefing was filed for this case.")}
    </p>
  </header>

  <dl class="grid grid-cols-3 border-y border-[#9b8264] py-3 text-center">
    <div><dt class="font-mono text-[8px] uppercase tracking-[0.12em] text-[#765d47]">{t("Day")}</dt><dd class="mt-1 font-serif text-lg font-semibold">{day}</dd></div>
    <div class="border-x border-[#9b8264]"><dt class="font-mono text-[8px] uppercase tracking-[0.12em] text-[#765d47]">{t("Days left")}</dt><dd class="mt-1 font-serif text-lg font-semibold">{daysRemaining}</dd></div>
    <div><dt class="font-mono text-[8px] uppercase tracking-[0.12em] text-[#765d47]">{t("Your desk")}</dt><dd class="mt-1 font-serif text-sm font-semibold">{t(role)}</dd></div>
  </dl>

  <section id="case-file-directives" aria-labelledby="case-directives-heading">
    <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">{t("Case directives · override standing orders")}</p>
    <h4 id="case-directives-heading" class="mt-1 font-serif text-xl font-semibold">{t("Special rules on record")}</h4>

    {#if specialRules.length > 0}
      <ul class="mt-4 grid gap-3 md:grid-cols-2">
        {#each specialRules as rule}
          <li id={`case-file-rule-${rule.id}`} class="border-l-4 border-[#754238] bg-[#dfcfaf] px-4 py-3">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <h5 class="font-serif text-base font-semibold">{rule.title}</h5>
              <span class="font-mono text-[8px] uppercase tracking-[0.12em] text-[#765d47]">{rule.triggered ? t("IN EFFECT") : t("ON FILE")}</span>
            </div>
            <p class="mt-2 text-sm leading-6 text-[#4f3e30]">{rule.text}</p>
          </li>
        {/each}
      </ul>
    {:else}
      <p id="case-file-no-directives" class="mt-4 border border-dashed border-[#9b8264] p-4 font-serif text-sm italic text-[#5f4a38]">{t("No public exception is currently on record. Follow the standing Field Rulebook.")}</p>
    {/if}
  </section>
</article>
