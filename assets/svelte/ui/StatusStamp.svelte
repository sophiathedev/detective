<script>
  let { tone = "neutral", children } = $props()
</script>

<span class={`noir-status-stamp noir-status-stamp-${tone}`}>
  {@render children?.()}
</span>
