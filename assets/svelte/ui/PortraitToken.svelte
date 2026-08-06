<script>
  import { useI18n } from "../i18n"

  let { name, role = "detective", seat = 1, size = "md" } = $props()
  const { t } = useI18n()

  let label = $derived(
    role === "chisel"
      ? t("Chisel portrait for {name}", { name })
      : t("Detective portrait for {name}", { name }),
  )
  let src = $derived(
    role === "chisel"
      ? "/images/ui/noir/portraits/chisel.webp"
      : `/images/ui/noir/portraits/detective-${Math.min(Math.max(seat, 1), 4)}.webp`,
  )
</script>

<img class={`noir-portrait noir-portrait-${size}`} {src} alt={label} draggable="false" />
