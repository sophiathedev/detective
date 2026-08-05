<script>
  import PortraitToken from "../ui/PortraitToken.svelte"

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
    <p>Chisel console</p>
    <span class:noir-connection-online={online} class="noir-connection-label">{connectionLabel}</span>
  </header>

  {#if chisel}
    <div class="noir-chisel-identity">
      <PortraitToken name={chisel.display_name} role="chisel" size="lg" />
      <div class="min-w-0">
        <h2 id="chisel-console-title" class="truncate font-serif text-xl font-semibold text-[#eadbbd]">
          {chisel.display_name}
        </h2>
        <p class="mt-1 font-mono text-[0.55rem] uppercase tracking-[0.14em] text-[#a98d63]">
          Keeper of the casebook
        </p>
      </div>
    </div>

    {#if isCurrentChisel}
      <div class="noir-chisel-private-ledger">
        <p class="noir-chisel-response-state">
          {pendingInterrogation ? "Response open" : "No pending response"}
        </p>
        <dl>
          {#each detectiveSlots as detective, index}
            <div>
              <dt>D{detective.seat ?? index + 1}</dt>
              <dd>{leverageByDetective[detective.id] ?? 0}</dd>
            </div>
          {/each}
        </dl>
      </div>
    {:else}
      <p class="noir-chisel-sealed-copy">Private controls sealed</p>
    {/if}
  {:else}
    <h2 id="chisel-console-title" class="noir-chisel-sealed-copy">Chisel unavailable</h2>
  {/if}
</section>
