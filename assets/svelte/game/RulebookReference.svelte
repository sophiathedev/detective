<script>
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let { role = "detective" } = $props()
</script>

<article id="rulebook-reference" class="grid gap-5 text-[#392d24]" aria-labelledby="rulebook-heading">
  <header class="border-b-2 border-[#76543d] pb-5">
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <p class="font-mono text-[9px] uppercase tracking-[0.18em] text-[#8c3f33]">{t("Standing orders · Los Angeles detail")}</p>
        <h3 id="rulebook-heading" class="mt-1 font-serif text-2xl font-semibold sm:text-3xl">{t("Field rulebook")}</h3>
      </div>
      <span class="rotate-[-2deg] border-2 border-[#7f342e] px-3 py-2 font-mono text-[9px] font-bold uppercase tracking-[0.16em] text-[#7f342e]">
        {role === "chisel" ? t("Chisel copy") : t("Detective copy")}
      </span>
    </div>
    <p class="mt-4 max-w-3xl font-serif text-base leading-7 text-[#4f3e30]">
      {t("Identify the suspect, weapon, and motive before the Day track expires. The server is the final authority for every cost, legal move, response, and verdict.")}
    </p>
  </header>

  <section id="rulebook-turn" class="grid gap-3 lg:grid-cols-[0.72fr_1.28fr]" aria-labelledby="rulebook-turn-heading">
    <div class="border-l-4 border-[#8b3b31] bg-[#d7c6a6] p-4">
      <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#765d47]">{t("01 · Your turn")}</p>
      <h4 id="rulebook-turn-heading" class="mt-1 font-serif text-xl font-semibold">{t("Four actions, one lead")}</h4>
      <p class="mt-2 text-sm leading-6 text-[#564433]">{t("A Detective receives 4 AP at the start of their turn. Initial placement at a highlighted Police Station is free.")}</p>
    </div>
    <ol class="grid gap-2 sm:grid-cols-2">
      <li class="border border-[#9b8264] bg-[#e5d7ba] p-3"><strong class="font-serif">{t("Move · 1 AP")}</strong><p class="mt-1 text-xs leading-5">{t("Click a highlighted location on the map. You may reach any location sharing a district; border locations connect districts for a later move.")}</p></li>
      <li class="border border-[#9b8264] bg-[#e5d7ba] p-3"><strong class="font-serif">{t("Search · 1 AP")}</strong><p class="mt-1 text-xs leading-5">{t("Search your location or a co-located suspect. A filed Search lead cannot be searched again.")}</p></li>
      <li class="border border-[#9b8264] bg-[#e5d7ba] p-3"><strong class="font-serif">{t("Question · 1 AP")}</strong><p class="mt-1 text-xs leading-5">{t("Question a suspect at your location about a discovered Case topic. A free follow-up must be resolved or declined immediately.")}</p></li>
      <li class="border border-[#9b8264] bg-[#e5d7ba] p-3"><strong class="font-serif">{t("Analyze · 1 AP")}</strong><p class="mt-1 text-xs leading-5">{t("Trade one action for $1 Scratch when the street has gone cold.")}</p></li>
    </ol>
  </section>

  <section id="rulebook-interrogation" class="border-y border-[#9b8264] py-5" aria-labelledby="rulebook-interrogation-heading">
    <div class="grid gap-5 lg:grid-cols-[1.1fr_0.9fr]">
      <div>
        <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#8c3f33]">{t("02 · ARC interrogation")}</p>
        <h4 id="rulebook-interrogation-heading" class="mt-1 font-serif text-xl font-semibold">{t("Accept, challenge, or spend leverage")}</h4>
        <ol class="mt-3 grid gap-2 text-sm leading-6">
          <li><span class="mr-2 font-mono text-[10px] font-bold text-[#8c3f33]">A</span>{t("The Chisel may allow the question or spend leverage to send a goon. The asking Detective may abandon it or pay $2 to continue.")}</li>
          <li><span class="mr-2 font-mono text-[10px] font-bold text-[#8c3f33]">R</span>{t("The Chisel selects one server-authorized response. Detective leverage forces the most useful available statement.")}</li>
          <li><span class="mr-2 font-mono text-[10px] font-bold text-[#8c3f33]">C</span>{t("The asking Detective accepts the statement or stakes one leverage marker to challenge it. The server resolves truth, reward, and penalty.")}</li>
        </ol>
      </div>
      <aside class="rotate-[0.4deg] border-2 border-[#76543d] bg-[#d6c29e] p-4">
        <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#765d47]">{t("Challenge outcome")}</p>
        <p class="mt-2 font-serif text-sm leading-6">{t("A successful challenge corrects the record. A failed challenge transfers the staked leverage to the Chisel. No client decides the result.")}</p>
      </aside>
    </div>
  </section>

  <section id="rulebook-street" aria-labelledby="rulebook-street-heading">
    <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#8c3f33]">{t("03 · Street economy")}</p>
    <h4 id="rulebook-street-heading" class="mt-1 font-serif text-xl font-semibold">{t("Scratch opens sealed doors")}</h4>
    <div class="mt-3 grid gap-3 sm:grid-cols-3">
      <div class="border-t-2 border-[#76543d] pt-3"><strong class="font-serif">{t("Kickback · 1 AP")}</strong><p class="mt-1 text-xs leading-5">{t("At a Mob Joint, collect the table payout once per Day.")}</p></div>
      <div class="border-t-2 border-[#76543d] pt-3"><strong class="font-serif">{t("Detective bribe · $2")}</strong><p class="mt-1 text-xs leading-5">{t("At the same location, pay to inspect one unknown Case card another Detective knows. Bribes cost no AP.")}</p></div>
      <div class="border-t-2 border-[#76543d] pt-3"><strong class="font-serif">{t("Officer bribe · $3")}</strong><p class="mt-1 text-xs leading-5">{t("At a Police Station, pay the desk officer to inspect an eligible unknown Case card. Bribes cost no AP.")}</p></div>
    </div>
  </section>

  <section id="rulebook-close-case" class="grid gap-4 bg-[#30261f] p-5 text-[#f1e2c3] sm:grid-cols-2" aria-labelledby="rulebook-close-heading">
    <div>
      <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#d99b77]">{t("04 · Close the case")}</p>
      <h4 id="rulebook-close-heading" class="mt-1 font-serif text-xl font-semibold">{t("Commit to the whole theory")}</h4>
      <p class="mt-2 text-sm leading-6 text-[#d9c8a8]">{t("Use your single Solve token only at the beginning of your turn, before spending any AP. Name one suspect, one known weapon, and one motive.")}</p>
    </div>
    <div class="border-l border-[#806d54] pl-4">
      <p class="font-serif text-sm leading-6">{t("A correct Solve closes the case immediately. If time expires, every Detective files one private final guess; the solution is revealed only after all envelopes are in.")}</p>
    </div>
  </section>

  <footer class="border-l-4 border-[#8c3f33] pl-4 text-xs leading-5 text-[#5e4938]">
    <strong class="font-serif text-sm">{t("Case directives outrank this guide.")}</strong>
    {t("Special actors, counter-surveillance, and triggered rules appear in the Case File when the server authorizes them.")}
  </footer>
</article>
