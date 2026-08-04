<script>
  let { name, role = "detective", seat = 1, size = "md" } = $props()

  let label = $derived(`${role === "chisel" ? "Chisel" : "Detective"} portrait for ${name}`)
  let src = $derived(
    role === "chisel"
      ? "/images/ui/noir/portraits/chisel.webp"
      : `/images/ui/noir/portraits/detective-${Math.min(Math.max(seat, 1), 4)}.webp`,
  )
</script>

<img class={`noir-portrait noir-portrait-${size}`} {src} alt={label} draggable="false" />
