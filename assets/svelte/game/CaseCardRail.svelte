<script>
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let {
    slots = [],
    players = [],
    inspectableCaseCardCodes = [],
    selectedCaseCardCode = null,
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
    return Math.min(Math.max(Number(slot.position) || 1, 1), 12)
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
    <div class="noir-case-card-face noir-case-card-faceup">
      <span>{slot.type}</span>
      <strong>{slot.code}</strong>
      <p>{slot.title}</p>
    </div>
  {:else if slot.status === "removed"}
    <div class="noir-case-card-face noir-case-card-removed">
      <span>{t("Evidence")}</span>
      <strong>{slot.code}</strong>
      <p>{t("Removed")}</p>
      <small>
        {slot.evidence_release_day ? t("Day {day}", { day: slot.evidence_release_day }) : t("Held")}
      </small>
    </div>
  {:else}
    <div class="noir-case-card-face noir-case-card-facedown" aria-hidden="true">
      <span>{slot.code}</span>
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
        style={`--case-slot-position: ${slotPosition(slot)};`}
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
