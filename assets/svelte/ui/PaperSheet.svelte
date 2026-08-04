<script>
  let {
    as = "article",
    id = undefined,
    class: className = "",
    labelledby = undefined,
    tilt = "none",
    children,
  } = $props()
</script>

<svelte:element
  this={as}
  {id}
  aria-labelledby={labelledby}
  data-tilt={tilt}
  class={`noir-paper-sheet ${className}`}
>
  {@render children?.()}
</svelte:element>
