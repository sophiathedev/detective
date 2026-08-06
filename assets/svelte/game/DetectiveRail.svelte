<script>
  import PortraitToken from "../ui/PortraitToken.svelte"

  let {
    players = [],
    currentDetectiveId = null,
    ownPlayerId = null,
    privateResources = null,
    locations = [],
    onlinePlayerIds = [],
    connectionSnapshotReceived = false,
    disconnectLabel = () => "OFFLINE",
  } = $props()

  let detectiveSlots = $derived(
    [1, 2, 3, 4].map((seat) =>
      players.find((player) => player.role === "detective" && player.seat === seat),
    ),
  )

  function connectionLabel(playerId) {
    if (!connectionSnapshotReceived) return "SYNCING"
    if (onlinePlayerIds.includes(playerId)) return "ONLINE"

    const detail = disconnectLabel(playerId)
    return detail && detail !== "OFFLINE" ? `OFFLINE ${detail}` : "OFFLINE"
  }

  function online(playerId) {
    return connectionSnapshotReceived && onlinePlayerIds.includes(playerId)
  }

  function locationName(locationId) {
    if (!locationId) return "Awaiting placement"

    return locations.find((location) => location.id === locationId)?.name ?? "Location unavailable"
  }
</script>

<section id="detective-rail" class="noir-detective-tray noir-wood-frame" aria-labelledby="detective-rail-title">
  <header class="noir-detective-tray-header">
    <p>Field unit</p>
    <h2 id="detective-rail-title">Detectives</h2>
  </header>

  <ol class="noir-detective-tray-list">
    {#each detectiveSlots as detective, index}
      {@const seat = index + 1}
      <li
        id={`detective-rail-slot-${seat}`}
        data-testid={`detective-rail-slot-${seat}`}
        class:noir-detective-slot-active={detective?.id === currentDetectiveId}
        class="noir-detective-slot"
        aria-current={detective?.id === currentDetectiveId ? "turn" : undefined}
      >
        {#if detective}
          <div class="relative shrink-0">
            <PortraitToken name={detective.display_name} role="detective" {seat} size="md" />
            <span
              class:noir-presence-lamp-online={online(detective.id)}
              class="noir-presence-lamp"
              aria-hidden="true"
            ></span>
          </div>

          <div class="min-w-0 flex-1">
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="noir-detective-slot-label">D{seat}</p>
                <p
                  class="noir-detective-name break-words font-serif text-sm font-semibold leading-tight text-[#eadbbd]"
                  title={detective.display_name}
                >{detective.display_name}</p>
              </div>
              <span
                class:noir-connection-online={online(detective.id)}
                class="noir-connection-label"
                role={connectionSnapshotReceived && !online(detective.id) ? "timer" : undefined}
              >{connectionLabel(detective.id)}</span>
            </div>

            <div class="noir-detective-public-stats">
              <span>AP {detective.actions_remaining}/4</span>
              <span class="noir-detective-location" title={locationName(detective.location_id)}>
                At {locationName(detective.location_id)}
              </span>
            </div>

            {#if ownPlayerId === detective.id && privateResources}
              <div class="noir-detective-private-stats">
                <span>Scratch {privateResources.scratch ?? 0}</span>
                <span>Leverage {privateResources.leverage ?? 0}</span>
              </div>
            {/if}
          </div>
        {:else}
          <div class="noir-detective-slot-empty">
            <span>D{seat}</span>
            <small>Open dossier</small>
          </div>
        {/if}
      </li>
    {/each}
  </ol>
</section>
