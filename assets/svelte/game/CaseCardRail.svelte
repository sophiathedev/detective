<script>
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  const caseCardCodes = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
  const boardSlotCenters = [4.7, 12.85, 21.15, 29.55, 37.7, 46, 54.25, 62.5, 70.9, 79.1, 87.4, 95.7]

  let {
    slots = [],
    players = [],
    inspectableCaseCardCodes = [],
    selectedCaseCardCode = null,
    zoom = 1,
    disabled = false,
    onSelectCaseCard = () => {},
  } = $props()

  let inspectableCodes = $derived(new Set(disabled ? [] : inspectableCaseCardCodes))

  let detectivesById = $derived(
    new Map(
      players
        .filter((player) => player.role === "detective")
        .map((player) => [player.id, player]),
    ),
  )

  function detective(playerId) {
    return detectivesById.get(playerId)
  }

  function detectiveLabel(playerId) {
    const player = detective(playerId)
    return player ? `D${player.seat} ${player.display_name}` : t("Unknown Detective")
  }

  function visibleKnowledgePlayerIds(slot) {
    return slot.status === "faceup" ? [] : (slot.knowledge_player_ids ?? [])
  }

  function slotPosition(slot) {
    const codePosition = caseCardCodes.indexOf(String(slot.code ?? "").toUpperCase()) + 1
    return Math.min(Math.max(codePosition || Number(slot.position) || 1, 1), 12)
  }

  function slotCenter(slot) {
    return boardSlotCenters[slotPosition(slot) - 1]
  }

  function cardBackUrl(code) {
    const normalized = String(code ?? "A").toLowerCase()
    return `/images/cards/dcoa/backs/${normalized}.webp`
  }

  function cardTemplateUrl(type) {
    if (type === "evidence") return "/images/cards/dcoa/templates/evidence.webp"
    if (type === "information" || type === "crime") return "/images/cards/dcoa/templates/information.webp"
    return "/images/cards/dcoa/templates/suspect.webp"
  }

  function cardFaceUrl(slot) {
    return slot.artwork_url || cardTemplateUrl(slot.type)
  }

  function retinaUrl(url) {
    return String(url).replace(/\.webp$/, "@2x.webp")
  }

  function compactUrl(url) {
    return String(url).replace(/\.webp$/, "-220.webp")
  }

  function cardImageDelivery(url) {
    const optimized = String(url).startsWith("/images/cards/dcoa/") && String(url).endsWith(".webp")

    return {
      src: url,
      srcset: optimized
        ? `${compactUrl(url)} 220w, ${url} 420w, ${retinaUrl(url)} 675w`
        : undefined,
      sizes: optimized ? `${(6.65 * Math.min(Math.max(Number(zoom) || 1, 1), 2.5)).toFixed(3)}vw` : undefined,
    }
  }

  function slotLabel(slot) {
    if (slot.status === "faceup") return t("Case {code} faceup: {title}", { code: slot.code, title: slot.title })

    const knowledge = visibleKnowledgePlayerIds(slot)
      .map(detectiveLabel)
      .join(", ")

    if (slot.status === "removed") {
      const holder = detectiveLabel(slot.evidence_holder_player_id)
      const release = slot.evidence_release_day
        ? t(" Returns faceup on Day {day}.", { day: slot.evidence_release_day })
        : t(" No automatic return is scheduled.")

      return t("Case {code} evidence removed by {holder}.{release} Known by {knowledge}.", { code: slot.code, holder, release, knowledge: knowledge || holder })
    }

    return t("Case {code} facedown.{knowledge}", { code: slot.code, knowledge: knowledge ? t(" Known by {knowledge}.", { knowledge }) : "" })
  }

  function selectCaseCard(slot) {
    if (!inspectableCodes.has(slot.code)) return
    onSelectCaseCard(slot)
  }
</script>

{#snippet cardFace(slot)}
  {#if slot.status === "faceup"}
    {@const image = cardImageDelivery(cardFaceUrl(slot))}
    <div
      class="noir-case-card-face noir-case-card-faceup"
      data-card-type={slot.type ?? "case"}
      data-card-code={slot.code}
      data-has-artwork={Boolean(slot.artwork_url)}
    >
      <img
        class="noir-case-card-art"
        src={image.src}
        srcset={image.srcset}
        sizes={image.sizes}
        decoding="async"
        fetchpriority="low"
        alt=""
        aria-hidden="true"
        draggable={false}
      />
      <div class="noir-case-card-copy">
        <span>{slot.type}</span>
        <p>{slot.title}</p>
        {#if (slot.type === "information" || slot.type === "crime") && slot.description}
          <small>{slot.description}</small>
        {/if}
      </div>
    </div>
  {:else if slot.status === "removed"}
    <div class="noir-case-card-face noir-case-card-removed" data-card-type="evidence">
      <i class="noir-case-card-staple" aria-hidden="true"></i>
      <span>{t("Evidence")}</span>
      <strong>{slot.code}</strong>
      <p>{t("Removed")}</p>
      <small>
        {slot.evidence_release_day ? t("Day {day}", { day: slot.evidence_release_day }) : t("Held")}
      </small>
    </div>
  {:else}
    {@const image = cardImageDelivery(cardBackUrl(slot.code))}
    <div
      class="noir-case-card-face noir-case-card-facedown"
      data-card-code={slot.code}
      aria-hidden="true"
    >
      <img
        class="noir-case-card-art"
        src={image.src}
        srcset={image.srcset}
        sizes={image.sizes}
        decoding="async"
        fetchpriority="low"
        alt=""
        draggable={false}
      />
    </div>
  {/if}
{/snippet}

<section
  id="case-card-rail"
  class="noir-case-card-rail"
  aria-label={t("Case cards and public knowledge markers")}
>
  <ol class="noir-case-card-grid">
    {#each slots as slot (slot.code)}
      {@const inspectable = inspectableCodes.has(slot.code)}
      <li
        id={`case-card-slot-${slot.code}`}
        data-testid={`case-card-slot-${slot.code}`}
        data-status={slot.status}
        class="noir-case-card-slot"
        style={`--case-slot-position: ${slotPosition(slot)}; --case-slot-center: ${slotCenter(slot)};`}
        aria-label={slotLabel(slot)}
      >
        {#if inspectable}
          <button
            id={`case-card-action-${slot.code}`}
            data-testid={`case-card-action-${slot.code}`}
            type="button"
            class:noir-case-card-action-selected={selectedCaseCardCode === slot.code}
            class="noir-case-card-action"
            aria-pressed={selectedCaseCardCode === slot.code}
            aria-label={t("{label} Open evidence folio.", { label: slotLabel(slot) })}
            onclick={() => selectCaseCard(slot)}
          >
            {@render cardFace(slot)}
          </button>
        {:else}
          {@render cardFace(slot)}
        {/if}

        <div class="noir-case-knowledge-rack" aria-hidden="true">
          {#each visibleKnowledgePlayerIds(slot) as playerId (playerId)}
            {@const owner = detective(playerId)}
            <span
              class="noir-case-knowledge-marker"
              data-seat={owner?.seat ?? 0}
              title={detectiveLabel(playerId)}
            >D{owner?.seat ?? "?"}</span>
          {/each}
        </div>
      </li>
    {/each}
  </ol>
</section>
