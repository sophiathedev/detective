<script>
  import { onDestroy } from "svelte"

  let {
    open = false,
    title = "Casebook",
    folioLabel = "Detective field folio",
    page = null,
    pages = [],
    onSelectPage = () => {},
    onClose = () => {},
    children,
  } = $props()

  let returnFocus = null
  let closeButton = $state(null)
  let dialog = $state(null)
  let wasOpen = false

  $effect(() => {
    if (open && !wasOpen && typeof document !== "undefined") {
      returnFocus = document.activeElement
      window.requestAnimationFrame(() => closeButton?.focus({ preventScroll: true }))
    } else if (!open && wasOpen) {
      restoreOpeningFocus()
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
    if (!open) return

    if (event.key === "Tab") {
      const controls = [
        ...(dialog?.querySelectorAll(
          "button:not(:disabled), a[href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex='0']",
        ) ?? []),
      ]

      if (controls.length === 0) {
        event.preventDefault()
        dialog?.focus({ preventScroll: true })
        return
      }

      const first = controls[0]
      const last = controls[controls.length - 1]
      const focusOutside = !dialog?.contains(document.activeElement)

      if (event.shiftKey && (focusOutside || document.activeElement === first)) {
        event.preventDefault()
        last.focus({ preventScroll: true })
      } else if (!event.shiftKey && (focusOutside || document.activeElement === last)) {
        event.preventDefault()
        first.focus({ preventScroll: true })
      }

      return
    }

    if (event.key !== "Escape") return

    event.preventDefault()
    event.stopPropagation()
    requestClose()
  }

  onDestroy(() => {
    if (open) restoreOpeningFocus()
  })
</script>

<svelte:window onkeydown={handleKeydown} />

{#if open}
  <div id="casebook-overlay" class="noir-casebook-backdrop">
    <div
      id="casebook-dialog"
      bind:this={dialog}
      class="noir-casebook-dialog noir-paper-sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="casebook-overlay-title"
      tabindex="-1"
    >
      <header class="noir-casebook-header">
        <div>
          <p>{folioLabel}</p>
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
