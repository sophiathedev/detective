<script>
  let {
    as = "section",
    id = undefined,
    class: className = "",
    labelledby = undefined,
    children,
  } = $props()
</script>

<svelte:element
  this={as}
  {id}
  aria-labelledby={labelledby}
  class={`noir-wood-frame ${className}`}
>
  {@render children?.()}
</svelte:element>
