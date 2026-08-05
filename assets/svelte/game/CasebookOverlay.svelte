<script>
  let {
    open = false,
    title = "Casebook",
    page = null,
    pages = [],
    onSelectPage = () => {},
    onClose = () => {},
    children,
  } = $props()

  let returnFocus = null
  let closeButton = $state(null)
  let wasOpen = false

  $effect(() => {
    if (open && !wasOpen && typeof document !== "undefined") {
      returnFocus = document.activeElement
      window.requestAnimationFrame(() => closeButton?.focus({ preventScroll: true }))
    }

    wasOpen = open
  })

  function restoreOpeningFocus() {
    if (typeof window === "undefined") return

    window.requestAnimationFrame(() => {
      if (returnFocus?.isConnected && typeof returnFocus.focus === "function") {
        returnFocus.focus({ preventScroll: true })
      }
    })
  }

  function requestClose() {
    onClose()
    restoreOpeningFocus()
  }

  function handleKeydown(event) {
    if (!open || event.key !== "Escape") return

    event.preventDefault()
    event.stopPropagation()
    requestClose()
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if open}
  <div id="casebook-overlay" class="noir-casebook-backdrop">
    <div
      id="casebook-dialog"
      class="noir-casebook-dialog noir-paper-sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="casebook-overlay-title"
    >
      <header class="noir-casebook-header">
        <div>
          <p>Detective field folio</p>
          <h2 id="casebook-overlay-title">{title}</h2>
        </div>
        <button
          id="close-casebook-overlay"
          bind:this={closeButton}
          type="button"
          class="noir-casebook-close"
          aria-label="Close casebook"
          onclick={requestClose}
        >
          <span aria-hidden="true">×</span>
        </button>
      </header>

      {#if pages.length > 0}
        <nav class="noir-casebook-page-tabs" aria-label="Casebook pages">
          {#each pages as entry (entry.id)}
            <button
              type="button"
              class:noir-casebook-page-tab-active={page === entry.id}
              class="noir-casebook-page-tab"
              aria-pressed={page === entry.id}
              onclick={() => onSelectPage(entry.id)}
            >
              {entry.label}
            </button>
          {/each}
        </nav>
      {/if}

      <div id="casebook-overlay-content" class="noir-casebook-content">
        {@render children?.()}
      </div>
    </div>
  </div>
{/if}
