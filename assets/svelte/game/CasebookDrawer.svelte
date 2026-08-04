<script>
  let {
    open = false,
    title = "Casebook",
    onClose = () => {},
    children,
  } = $props()

  let returnFocus = null
  let wasOpen = false

  $effect(() => {
    if (open && !wasOpen && typeof document !== "undefined") {
      returnFocus = document.activeElement
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
  <aside
    id="casebook-drawer"
    class="casebook-drawer"
    aria-labelledby="casebook-drawer-title"
    tabindex="-1"
  >
    <header class="casebook-drawer-header">
      <div>
        <p class="casebook-drawer-kicker">Detective field folio</p>
        <h2 id="casebook-drawer-title" class="casebook-drawer-title">{title}</h2>
      </div>
      <button
        id="close-casebook-drawer"
        type="button"
        class="casebook-drawer-close"
        aria-label="Close casebook"
        onclick={requestClose}
      >
        <span aria-hidden="true">×</span>
      </button>
    </header>

    <div id="casebook-drawer-content" class="casebook-drawer-content">
      {@render children?.()}
    </div>
  </aside>
{/if}
