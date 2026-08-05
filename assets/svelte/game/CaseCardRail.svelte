<script>
  let { slots = [], players = [] } = $props()

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
    return player ? `D${player.seat} ${player.display_name}` : "Unknown Detective"
  }

  function visibleKnowledgePlayerIds(slot) {
    return slot.status === "faceup" ? [] : (slot.knowledge_player_ids ?? [])
  }

  function slotPosition(slot) {
    return Math.min(Math.max(Number(slot.position) || 1, 1), 12)
  }

  function slotLabel(slot) {
    if (slot.status === "faceup") return `Case ${slot.code} faceup: ${slot.title}`

    const knowledge = visibleKnowledgePlayerIds(slot)
      .map(detectiveLabel)
      .join(", ")

    if (slot.status === "removed") {
      const holder = detectiveLabel(slot.evidence_holder_player_id)
      const release = slot.evidence_release_day
        ? ` Returns faceup on Day ${slot.evidence_release_day}.`
        : " No automatic return is scheduled."

      return `Case ${slot.code} evidence removed by ${holder}.${release} Known by ${knowledge || holder}.`
    }

    return `Case ${slot.code} facedown.${knowledge ? ` Known by ${knowledge}.` : ""}`
  }
</script>

<section
  id="case-card-rail"
  class="noir-case-card-rail"
  aria-label="Case cards and public knowledge markers"
>
  <ol class="noir-case-card-grid">
    {#each slots as slot (slot.code)}
      <li
        id={`case-card-slot-${slot.code}`}
        data-testid={`case-card-slot-${slot.code}`}
        data-status={slot.status}
        class="noir-case-card-slot"
        style={`--case-slot-position: ${slotPosition(slot)};`}
        aria-label={slotLabel(slot)}
      >
        {#if slot.status === "faceup"}
          <div class="noir-case-card-face noir-case-card-faceup">
            <span>{slot.type}</span>
            <strong>{slot.code}</strong>
            <p>{slot.title}</p>
          </div>
        {:else if slot.status === "removed"}
          <div class="noir-case-card-face noir-case-card-removed">
            <span>Evidence</span>
            <strong>{slot.code}</strong>
            <p>Removed</p>
            <small>
              {slot.evidence_release_day ? `Day ${slot.evidence_release_day}` : "Held"}
            </small>
          </div>
        {:else}
          <div class="noir-case-card-face noir-case-card-facedown" aria-hidden="true">
            <span>{slot.code}</span>
          </div>
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
