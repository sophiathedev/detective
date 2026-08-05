<script>
  import PaperSheet from "./ui/PaperSheet.svelte"
  import StatusStamp from "./ui/StatusStamp.svelte"
  import WoodFrame from "./ui/WoodFrame.svelte"

  let { invite = null, error = null } = $props()
</script>

<div id="invite-shell" class="min-h-[calc(100dvh-3.5rem)] px-4 py-10 text-stone-100 sm:px-6 sm:py-16">
  <WoodFrame
    as="main"
    labelledby="invite-title"
    class="mx-auto grid max-w-5xl overflow-hidden p-3 sm:p-5 lg:grid-cols-[minmax(18rem,0.7fr)_minmax(0,1fr)]"
  >
    <div class="relative min-h-72 overflow-hidden border border-[var(--noir-gold-700)] bg-[var(--noir-ebony-900)] lg:min-h-[38rem]">
      <div class="pointer-events-none absolute inset-0" aria-hidden="true">
        <div class="absolute inset-0 opacity-30 [background-image:linear-gradient(var(--noir-gold-700)_1px,transparent_1px),linear-gradient(90deg,var(--noir-gold-700)_1px,transparent_1px)] [background-size:3rem_3rem]"></div>
        <div class="absolute -left-20 top-1/2 h-4 w-[150%] -rotate-12 border-y border-[var(--noir-gold-700)] bg-black/30"></div>
        <div class="absolute left-1/2 top-1/2 size-52 -translate-x-1/2 -translate-y-1/2 rounded-full border border-[var(--noir-red-500)] opacity-40"></div>
      </div>

      <div class="absolute inset-x-8 top-10 border border-[var(--noir-gold-700)] bg-[var(--noir-ebony-800)] p-5 sm:top-14">
        <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-[var(--noir-gold-500)]">City dispatch</p>
        <p class="mt-2 font-serif text-xl text-stone-200">Private delivery · recipient only</p>
      </div>

      <svg
        class="absolute bottom-10 left-1/2 size-44 -translate-x-1/2 drop-shadow-[0_1rem_1.5rem_rgba(0,0,0,0.65)]"
        viewBox="0 0 180 180"
        aria-hidden="true"
      >
        <path d="M90 8l14 11 18-4 8 18 18 7-4 19 12 14-12 15 4 19-18 7-8 18-18-4-14 11-14-11-18 4-8-18-18-7 4-19-12-15 12-14-4-19 18-7 8-18 18 4z" fill="#641d18" stroke="#c2a35f" stroke-width="3" />
        <circle cx="90" cy="73" r="43" fill="#7b241e" stroke="#3b110e" stroke-width="3" />
        <path d="M60 86c18-20 42-20 60 0M67 61h46M90 43v63" fill="none" stroke="#d5b66d" stroke-width="4" stroke-linecap="round" opacity=".82" />
        <text x="90" y="145" text-anchor="middle" fill="#eadbbd" font-family="ui-monospace, monospace" font-size="11" letter-spacing="3">SEALED</text>
      </svg>
    </div>

    <PaperSheet
      as="section"
      id="invite-summons"
      labelledby="invite-title"
      tilt="right"
      class="m-2 flex flex-col justify-center p-6 sm:m-4 sm:p-10 lg:m-6"
    >
      {#if invite}
        <div class="flex flex-wrap items-center justify-between gap-3">
          <StatusStamp tone="sealed">Official summons</StatusStamp>
          <span class="font-mono text-xs font-semibold tracking-[0.16em] text-[var(--noir-red-700)]">{invite.room_code}</span>
        </div>

        <h1 id="invite-title" class="mt-6 font-serif text-4xl font-semibold leading-tight tracking-[-0.035em] sm:text-5xl">
          {invite.game_title}
        </h1>
        <p class="mt-3 font-serif text-lg italic text-[#66513c]">{invite.case_title}</p>

        <dl id="invite-room-details" class="mt-8 divide-y divide-[var(--noir-paper-500)] border-y border-[var(--noir-paper-500)] text-sm">
          <div class="flex justify-between gap-6 py-4">
            <dt class="font-mono text-xs uppercase tracking-[0.1em] text-[#806b50]">Chisel</dt>
            <dd class="text-right font-semibold">{invite.host_name}</dd>
          </div>
          <div class="flex justify-between gap-6 py-4">
            <dt class="font-mono text-xs uppercase tracking-[0.1em] text-[#806b50]">Detectives</dt>
            <dd class="font-mono font-semibold">{invite.detective_count}/{invite.max_detectives}</dd>
          </div>
          <div class="flex justify-between gap-6 py-4">
            <dt class="font-mono text-xs uppercase tracking-[0.1em] text-[#806b50]">Places left</dt>
            <dd class="font-mono font-semibold">{invite.places_left}</dd>
          </div>
        </dl>

        {#if error}
          <div class="mt-6 flex items-start gap-3">
            <StatusStamp tone="danger">Unable</StatusStamp>
            <p id="invite-error" role="alert" class="text-sm leading-6 text-[var(--noir-red-700)]">{error}</p>
          </div>
        {/if}

        <button
          id="accept-game-invite"
          type="button"
          phx-click="accept_invite"
          aria-label="Accept case invitation"
          class="mt-8 inline-flex min-h-12 cursor-pointer items-center justify-center bg-[var(--noir-red-700)] px-5 py-3 text-sm font-semibold text-[var(--noir-paper-100)] shadow-[0_0.3rem_0_#35100d] transition hover:bg-[var(--noir-red-500)] active:translate-y-0.5 active:shadow-[0_0.1rem_0_#35100d] focus-visible:outline-3 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-focus)]"
        >
          {invite.membership_status === "active" ? "Return to room" : "Join as detective"}
        </button>
        <p class="mt-3 text-xs leading-5 text-[#705a42]">Membership is recorded only after you confirm this summons.</p>
      {:else}
        <StatusStamp tone="danger">Invitation closed</StatusStamp>
        <h1 id="invite-title" class="mt-6 font-serif text-4xl font-semibold tracking-tight">This file is closed.</h1>
        <p id="invite-error" role="alert" class="mt-5 text-sm leading-6 text-[var(--noir-red-700)]">
          {error ?? "This invitation cannot be used."}
        </p>
        <a
          id="invite-back-dashboard"
          href="/dashboard"
          class="noir-physical-button mt-8 inline-flex w-fit items-center justify-center px-5 text-sm font-semibold"
        >
          Back to dashboard
        </a>
      {/if}
    </PaperSheet>
  </WoodFrame>
</div>
