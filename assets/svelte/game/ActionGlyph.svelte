<script>
  let { name = "casebook" } = $props()
</script>

<svg
  class="noir-action-glyph-art"
  viewBox="0 0 24 24"
  fill="none"
  aria-hidden="true"
  focusable="false"
>
  {#if name === "place"}
    <path d="M12 21s6-5.2 6-11A6 6 0 0 0 6 10c0 5.8 6 11 6 11Z" />
    <circle cx="12" cy="10" r="2.2" />
  {:else if name === "move"}
    <path d="M4 18c2.5-6.5 5.5 1 8-5s5-3.5 8-8" />
    <path d="m15 5 5-1-1 5" />
    <circle cx="4" cy="18" r="1.5" />
  {:else if name === "search_location"}
    <path d="M4 19h10M6 16V8h7v8M8.5 11h2M8.5 14h2" />
    <circle cx="16.5" cy="15.5" r="3.5" />
    <path d="m19 18 2 2" />
  {:else if name === "search_suspect"}
    <circle cx="9" cy="8" r="3" />
    <path d="M3.8 17c.7-3 2.4-4.5 5.2-4.5 1.4 0 2.6.4 3.5 1.2" />
    <circle cx="16.5" cy="15.5" r="3.5" />
    <path d="m19 18 2 2" />
  {:else if name === "interrogate"}
    <path d="M4 5h16v11H9l-5 4V5Z" />
    <path d="M9 9.5h.01M12 9.5h.01M15 9.5h.01" />
  {:else if name === "analyze"}
    <circle cx="6" cy="7" r="2" />
    <circle cx="18" cy="6" r="2" />
    <circle cx="16" cy="18" r="2" />
    <circle cx="7" cy="17" r="2" />
    <path d="m8 7 8-1M17.5 8l-1 8M14 18l-5-1M7 9v6M8 8.5l7 7" />
  {:else if name === "kickback"}
    <circle cx="12" cy="12" r="8" />
    <path d="M14.8 8.5c-.7-.7-1.7-1-2.8-1-1.7 0-3 .8-3 2s1 1.8 3 2.2 3 1 3 2.3-1.3 2.5-3 2.5c-1.2 0-2.3-.4-3-1.2M12 5.5v13" />
  {:else if name === "bribe_detective"}
    <circle cx="8" cy="8" r="3" />
    <path d="M3.5 17c.7-3 2.2-4.5 4.5-4.5 1.3 0 2.4.4 3.2 1.2" />
    <circle cx="16.5" cy="15.5" r="4" />
    <path d="M16.5 13v5M15 14h2.2c1.5 0 1.5 2 0 2H15" />
  {:else if name === "bribe_officer"}
    <path d="m8 4 4-2 4 2v5c0 3-1.4 5-4 6.5C9.4 14 8 12 8 9V4Z" />
    <circle cx="16.5" cy="16" r="4" />
    <path d="M16.5 13.5v5M15 14.5h2.2c1.5 0 1.5 2 0 2H15" />
  {:else if name === "skip_free_question"}
    <circle cx="12" cy="12" r="8" />
    <path d="m6.5 17.5 11-11M9.5 9a2.5 2.5 0 0 1 4.7 1.2c0 1.8-2.2 2-2.2 3.5M12 17h.01" />
  {:else if name === "accuse"}
    <circle cx="12" cy="12" r="7" />
    <circle cx="12" cy="12" r="2.5" />
    <path d="M12 2v4M12 18v4M2 12h4M18 12h4" />
  {:else if name === "submit_final_guess"}
    <path d="M5 4h14v16H5zM8 8h8M8 11h8M8 14h4" />
    <path d="m14 16 1.5 1.5L19 14" />
  {:else if name === "end_turn"}
    <circle cx="11" cy="12" r="7" />
    <path d="M11 8v4l3 2M17 6h4v4M21 6l-3 3" />
  {:else if name === "concede_game"}
    <path d="M5 3h14v18H5zM8 7h8M8 11h8M8 15h5" />
    <path d="m14.5 15 4 4M18.5 15l-4 4" />
  {:else}
    <path d="M3 5.5c3-1 6-.7 9 1.5v13c-3-2.2-6-2.5-9-1.5v-13ZM21 5.5c-3-1-6-.7-9 1.5v13c3-2.2 6-2.5 9-1.5v-13Z" />
    <path d="M6 9h3M6 12h3M15 9h3M15 12h3" />
  {/if}
</svg>
