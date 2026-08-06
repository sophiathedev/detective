<script>
  import PaperSheet from "./ui/PaperSheet.svelte"
  import StatusStamp from "./ui/StatusStamp.svelte"
  import WoodFrame from "./ui/WoodFrame.svelte"
  import { initializeI18n } from "./i18n"

  let {
    form = {
      fields: { title: "", case_version_id: "", max_detectives: "", invite_hours: "24" },
      errors: {},
    },
    case_options = [],
    global_error = null,
    created_room = null,
    locale = "en",
  } = $props()
  const { t } = initializeI18n(() => locale)

  let copied = $state(false)
  let fields = $derived(form.fields ?? {})
  let errors = $derived(form.errors ?? {})
  let has_cases = $derived(case_options.length > 0)

  function firstError(field) {
    return errors[field]?.[0]
  }

  async function copyInvite() {
    if (!created_room?.invite_url || !navigator.clipboard) return

    await navigator.clipboard.writeText(created_room.invite_url)
    copied = true
    window.setTimeout(() => (copied = false), 1800)
  }
</script>

<div id="create-game-shell" class="min-h-[calc(100dvh-3.5rem)] px-4 py-8 text-stone-100 sm:px-6 sm:py-12 lg:px-10">
  <main class="mx-auto max-w-[92rem]">
    <nav id="create-game-header" class="mb-6 flex items-center justify-between gap-4" aria-label={t("Create game navigation")}>
      <a
        id="create-game-back"
        href="/dashboard"
        class="inline-flex min-h-11 items-center gap-3 text-sm font-medium text-stone-300 transition hover:text-[var(--noir-gold-500)] focus-visible:outline-2 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-focus)]"
      >
        <span aria-hidden="true">←</span>
        {t("Case cabinet")}
      </a>
      <span class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--noir-gold-500)]">{t("Room intake")}</span>
    </nav>

    <WoodFrame
      as="section"
      labelledby="create-game-title"
      class="grid gap-3 overflow-hidden p-3 sm:p-5 lg:grid-cols-[minmax(0,1.15fr)_minmax(22rem,0.65fr)]"
    >
      <PaperSheet
        as="section"
        id="create-game-document"
        labelledby="create-game-title"
        tilt="left"
        class="p-6 sm:p-9 lg:p-11"
      >
        <div id="create-game-form-section">
          <div class="flex flex-wrap items-start justify-between gap-4 border-b border-[var(--noir-paper-500)] pb-6">
            <div>
              <p class="font-mono text-xs uppercase tracking-[0.2em] text-[var(--noir-red-700)]">{t("Open a case room")}</p>
              <h1 id="create-game-title" class="mt-3 font-serif text-4xl font-semibold tracking-[-0.035em] sm:text-5xl">
                {t("Case opening order")}
              </h1>
              <p class="mt-3 max-w-2xl text-sm leading-6 text-[#66513c]">
                {t("Select a published file and seal the room limits. You enter the lobby as its Chisel and host.")}
              </p>
            </div>
            <StatusStamp tone="sealed">{t("Host copy")}</StatusStamp>
          </div>

          {#if global_error}
            <div id="create-game-global-error" class="mt-6 flex items-start gap-3" role="alert">
              <StatusStamp tone="danger">{t("Rejected")}</StatusStamp>
              <p class="text-sm leading-6 text-[var(--noir-red-700)]">{t(global_error)}</p>
            </div>
          {/if}

          {#if !has_cases}
            <div id="case-catalog-empty" class="mt-7 border border-[var(--noir-red-700)] bg-[#d8c7a5] p-5" role="status">
              <p class="font-serif text-lg font-semibold">{t("No published cases available")}</p>
              <p class="mt-2 text-sm leading-6 text-[#66513c]">
                {t("A published, immutable case version is required before a room can be created.")}
              </p>
            </div>
          {/if}

          <form
            id="create-game-form"
            class="mt-8 space-y-7"
            phx-change="validate"
            phx-submit="save"
            class:hidden={created_room}
          >
            <div class="space-y-2">
              <label for="game-title" class="block font-mono text-xs font-semibold uppercase tracking-[0.1em]">{t("Room name")}</label>
              <input
                id="game-title"
                name="game[title]"
                type="text"
                value={fields.title ?? ""}
                required
                minlength="3"
                maxlength="80"
                autocomplete="off"
                placeholder={t("The midnight dossier")}
                aria-invalid={firstError("title") ? "true" : undefined}
                aria-describedby={firstError("title") ? "game-title-error" : "game-title-help"}
                class="noir-field px-4 py-3 text-base"
              />
              {#if firstError("title")}
                <p id="game-title-error" class="text-sm text-[var(--noir-red-700)]">{firstError("title")}</p>
              {:else}
                <p id="game-title-help" class="text-sm text-[#715a42]">{t("Printed on every invitation and player tray.")}</p>
              {/if}
            </div>

            <fieldset aria-describedby={firstError("case_version_id") ? "game-case-version-error" : "game-case-version-help"}>
              <legend class="font-mono text-xs font-semibold uppercase tracking-[0.1em]">{t("Published case")}</legend>
              <div class="mt-3 grid gap-3 md:grid-cols-2">
                {#each case_options as option (option.value)}
                  <label class="noir-case-choice">
                    <input
                      type="radio"
                      name="game[case_version_id]"
                      value={option.value}
                      checked={String(fields.case_version_id ?? "") === String(option.value)}
                      required
                    />
                    <span class="font-serif text-lg font-semibold">{option.label}</span>
                    <span class="text-sm leading-5 text-[#66513c]">{option.description}</span>
                  </label>
                {/each}
              </div>
              {#if firstError("case_version_id")}
                <p id="game-case-version-error" class="mt-2 text-sm text-[var(--noir-red-700)]">{firstError("case_version_id")}</p>
              {:else}
                <p id="game-case-version-help" class="mt-2 text-sm text-[#715a42]">{t("Only published versions may be sealed into a game.")}</p>
              {/if}
            </fieldset>

            <div class="grid gap-5 sm:grid-cols-2">
              <div class="space-y-2">
                <label for="game-max-detectives" class="block font-mono text-xs font-semibold uppercase tracking-[0.1em]">
                  {t("Detective seats")}
                </label>
                <select
                  id="game-max-detectives"
                  name="game[max_detectives]"
                  required
                  aria-invalid={firstError("max_detectives") ? "true" : undefined}
                  aria-describedby={firstError("max_detectives") ? "game-max-detectives-error" : "game-max-detectives-help"}
                  class="noir-field px-4 py-3 text-base"
                >
                  <option value="" selected={(fields.max_detectives ?? "") === ""}>{t("Choose capacity")}</option>
                  {#each [2, 3, 4] as count}
                    <option value={count} selected={String(fields.max_detectives ?? "") === String(count)}>
                      {t("{count} detectives", { count })}
                    </option>
                  {/each}
                </select>
                {#if firstError("max_detectives")}
                  <p id="game-max-detectives-error" class="text-sm text-[var(--noir-red-700)]">{firstError("max_detectives")}</p>
                {:else}
                  <p id="game-max-detectives-help" class="text-sm text-[#715a42]">{t("Classic mode: 2–4 Detectives plus one Chisel.")}</p>
                {/if}
              </div>

              <div class="space-y-2">
                <label for="game-invite-hours" class="block font-mono text-xs font-semibold uppercase tracking-[0.1em]">
                  {t("Invite expires")}
                </label>
                <select id="game-invite-hours" name="game[invite_hours]" required class="noir-field px-4 py-3 text-base">
                  {#each [["1", "1 hour"], ["6", "6 hours"], ["24", "24 hours"], ["72", "3 days"]] as option}
                    <option value={option[0]} selected={String(fields.invite_hours ?? "24") === option[0]}>{t(option[1])}</option>
                  {/each}
                </select>
                <p class="text-sm text-[#715a42]">{t("The link can be revoked earlier from the lobby.")}</p>
              </div>
            </div>

            <div class="flex flex-col-reverse gap-3 border-t border-[var(--noir-paper-500)] pt-6 sm:flex-row sm:items-center sm:justify-between">
              <a
                id="create-game-cancel"
                href="/dashboard"
                class="inline-flex min-h-11 items-center justify-center px-4 py-2.5 text-sm font-semibold text-[var(--noir-ink-900)] transition hover:text-[var(--noir-red-700)] focus-visible:outline-2 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-red-700)]"
              >
                {t("Cancel")}
              </a>
              <button
                id="create-game-submit"
                type="submit"
                disabled={!has_cases}
                phx-disable-with={t("Creating game...")}
                class="inline-flex min-h-12 cursor-pointer items-center justify-center bg-[var(--noir-red-700)] px-6 py-3 text-sm font-semibold text-[var(--noir-paper-100)] shadow-[0_0.3rem_0_#35100d] transition hover:bg-[var(--noir-red-500)] active:translate-y-0.5 active:shadow-[0_0.1rem_0_#35100d] focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-focus)] disabled:cursor-not-allowed disabled:opacity-45"
              >
                {t("Seal and create room")}
              </button>
            </div>
          </form>
        </div>
      </PaperSheet>

      <aside
        class="relative min-h-96 overflow-hidden border border-[var(--noir-gold-700)] bg-[var(--noir-ebony-900)] p-5 sm:p-7"
        aria-labelledby={created_room ? "created-room-title" : "dispatch-title"}
      >
        <div class="pointer-events-none absolute inset-0 opacity-35" aria-hidden="true">
          <div class="absolute left-[18%] top-0 h-full w-px rotate-12 bg-[var(--noir-gold-700)]"></div>
          <div class="absolute right-[12%] top-0 h-full w-px -rotate-12 bg-[var(--noir-gold-700)]"></div>
          <div class="absolute left-1/2 top-28 size-44 -translate-x-1/2 rounded-full border border-[var(--noir-red-500)]"></div>
        </div>

        {#if created_room}
          <section id="created-room" class="noir-paper-sheet relative mt-8 p-5 sm:p-7" aria-labelledby="created-room-title">
            <StatusStamp tone="ready">{t("Room {code}", { code: created_room.room_code })}</StatusStamp>
            <h2 id="created-room-title" class="mt-5 font-serif text-3xl font-semibold">{t("Dispatch ready")}</h2>
            <p class="mt-3 text-sm leading-6 text-[#66513c]">
              {t("Copy this raw invitation now. Its token disappears after reload and is never stored in plain text.")}
            </p>
            <div class="mt-5 grid gap-2">
              <input
                id="created-room-invite-url"
                aria-label={t("Invitation URL")}
                readonly
                value={created_room.invite_url}
                class="noir-field px-3 py-2 font-mono text-xs"
              />
              <button
                id="created-room-copy-invite"
                type="button"
                onclick={copyInvite}
                class="noir-physical-button px-4 text-sm font-semibold"
              >
                {copied ? t("Copied") : t("Copy invitation")}
              </button>
            </div>
            <a
              id="created-room-enter-lobby"
              href={created_room.lobby_path}
              class="mt-4 inline-flex min-h-11 w-full items-center justify-center bg-[var(--noir-red-700)] px-5 text-sm font-semibold text-[var(--noir-paper-100)] transition hover:bg-[var(--noir-red-500)] focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-focus)]"
            >
              {t("Enter lobby")}
            </a>
          </section>
        {:else}
          <div class="relative flex h-full min-h-80 flex-col justify-between">
            <div>
              <p class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--noir-gold-500)]">{t("Chisel authority")}</p>
              <h2 id="dispatch-title" class="mt-3 max-w-sm font-serif text-3xl font-semibold">{t("A room becomes real only after the server seals it.")}</h2>
            </div>
            <div class="border-l-2 border-[var(--noir-red-500)] pl-4">
              <p class="text-sm leading-6 text-stone-300">
                {t("Membership, capacity, published case version, and invitation expiry remain server-enforced.")}
              </p>
            </div>
          </div>
        {/if}
      </aside>
    </WoodFrame>
  </main>
</div>
