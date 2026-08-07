<script>
  import PortraitToken from "../ui/PortraitToken.svelte"
  import { useI18n } from "../i18n"

  const { t } = useI18n()

  let {
    players = [],
    currentDetectiveId = null,
    ownPlayerId = null,
    privateResources = null,
    locations = [],
    onlinePlayerIds = [],
    connectionSnapshotReceived = false,
    archived = false,
    disconnectLabel = () => "OFFLINE",
  } = $props()

  let detectiveSlots = $derived(
    [1, 2, 3, 4].map((seat) =>
      players.find((player) => player.role === "detective" && player.seat === seat),
    ),
  )

  function connectionLabel(playerId) {
    if (archived) return t("ARCHIVED")
    if (!connectionSnapshotReceived) return t("SYNCING")
    if (onlinePlayerIds.includes(playerId)) return t("ONLINE")

    const detail = disconnectLabel(playerId)
    return detail && detail !== "OFFLINE" ? t("OFFLINE {detail}", { detail }) : t("OFFLINE")
  }

  function online(playerId) {
    return connectionSnapshotReceived && onlinePlayerIds.includes(playerId)
  }

  function locationName(locationId) {
    if (!locationId) return t("Awaiting placement")

    return locations.find((location) => location.id === locationId)?.name ?? t("Location unavailable")
  }

  function actionPoints(value) {
    const points = Number.isFinite(value) ? value : 0
    return Math.max(0, Math.min(4, points))
  }
</script>

<section id="detective-rail" class="noir-detective-tray noir-wood-frame" aria-labelledby="detective-rail-title">
  <header class="noir-detective-tray-header">
    <p>{t("Field unit")}</p>
    <h2 id="detective-rail-title">{t("Detectives")}</h2>
  </header>

  <ol class="noir-detective-tray-list">
    {#each detectiveSlots as detective, index}
      {@const seat = index + 1}
      <li
        id={`detective-rail-slot-${seat}`}
        data-testid={`detective-rail-slot-${seat}`}
        data-seat={seat}
        data-occupied={Boolean(detective)}
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
                role={!archived && connectionSnapshotReceived && !online(detective.id) ? "timer" : undefined}
              >{connectionLabel(detective.id)}</span>
            </div>

            <div class="noir-detective-public-stats">
              <div
                class="noir-ap-meter"
                role="img"
                aria-label={t("{count} of 4 actions remaining", { count: actionPoints(detective.actions_remaining) })}
              >
                <span class="noir-resource-caption" aria-hidden="true">{t("Actions")}</span>
                <span class="noir-ap-pips" aria-hidden="true">
                  {#each [1, 2, 3, 4] as point}
                    <span
                      class:noir-ap-pip-spent={point > actionPoints(detective.actions_remaining)}
                      class="noir-ap-pip"
                    ></span>
                  {/each}
                </span>
                <strong aria-hidden="true">{actionPoints(detective.actions_remaining)}</strong>
              </div>
              <span class="noir-detective-location" title={locationName(detective.location_id)}>
                <svg viewBox="0 0 16 16" aria-hidden="true" focusable="false">
                  <path d="M8 14s4-3.6 4-7.5a4 4 0 1 0-8 0C4 10.4 8 14 8 14Z" />
                  <circle cx="8" cy="6.5" r="1.4" />
                </svg>
                <span>{t("At {location}", { location: locationName(detective.location_id) })}</span>
              </span>
            </div>

            {#if ownPlayerId === detective.id && privateResources}
              <div class="noir-detective-private-stats">
                <div
                  class="noir-resource-counter"
                  role="img"
                  aria-label={t("Scratch: {amount}", { amount: privateResources.scratch ?? 0 })}
                >
                  <span class="noir-scratch-coin" aria-hidden="true">$</span>
                  <span aria-hidden="true">
                    <small>{t("Scratch")}</small>
                    <strong>{privateResources.scratch ?? 0}</strong>
                  </span>
                </div>
                <div
                  class="noir-resource-counter"
                  role="img"
                  aria-label={t("Leverage: {amount}", { amount: privateResources.leverage ?? 0 })}
                >
                  <span class="noir-leverage-marker" aria-hidden="true">L</span>
                  <span aria-hidden="true">
                    <small>{t("Leverage")}</small>
                    <strong>{privateResources.leverage ?? 0}</strong>
                  </span>
                </div>
              </div>
            {/if}
          </div>
        {:else}
          <div class="noir-detective-slot-empty">
            <span>D{seat}</span>
            <small>{t("Open dossier")}</small>
          </div>
        {/if}
      </li>
    {/each}
  </ol>
</section>
