<script>
  import PortraitToken from "../ui/PortraitToken.svelte"
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let {
    chisel = null,
    isCurrentChisel = false,
    pendingInterrogation = null,
    leverageByDetective = {},
    detectiveSlots = [],
    online = false,
    connectionLabel = "OFFLINE",
  } = $props()
</script>

<section
  id="chisel-console"
  data-testid="chisel-console"
  class="noir-chisel-console noir-wood-frame"
  aria-labelledby="chisel-console-title"
>
  <header class="noir-chisel-console-header">
    <p>{t("Chisel console")}</p>
    <span class:noir-connection-online={online} class="noir-connection-label">{t(connectionLabel)}</span>
  </header>

  {#if chisel}
    <div class="noir-chisel-identity">
      <PortraitToken name={chisel.display_name} role="chisel" size="lg" />
      <div class="min-w-0">
        <h2 id="chisel-console-title" class="truncate font-serif text-xl font-semibold text-[#eadbbd]">
          {chisel.display_name}
        </h2>
        <p class="mt-1 font-mono text-[0.55rem] uppercase tracking-[0.14em] text-[#a98d63]">
          {t("Keeper of the casebook")}
        </p>
      </div>
    </div>

    {#if isCurrentChisel}
      <div class="noir-chisel-private-ledger">
        <p class="noir-chisel-response-state">
          {pendingInterrogation ? t("Question waiting") : t("Waiting for a question")}
        </p>
        <p class="noir-chisel-leverage-label">{t("Leverage markers")}</p>
        <dl>
          {#each detectiveSlots as detective, index}
            <div>
              <dt>D{detective.seat ?? index + 1}</dt>
              <dd
                role="img"
                aria-label={t("{count} leverage held for Detective {seat}", { count: leverageByDetective[detective.id] ?? 0, seat: detective.seat ?? index + 1 })}
              >
                <span class="noir-leverage-marker" aria-hidden="true">L</span>
                <strong aria-hidden="true">{leverageByDetective[detective.id] ?? 0}</strong>
              </dd>
            </div>
          {/each}
        </dl>
      </div>
    {:else}
      <p class="noir-chisel-sealed-copy">{t("Chisel notes remain private")}</p>
    {/if}
  {:else}
    <h2 id="chisel-console-title" class="noir-chisel-sealed-copy">{t("Chisel unavailable")}</h2>
  {/if}
</section>
