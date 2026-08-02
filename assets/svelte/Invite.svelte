<script>
  let { invite = null, error = null } = $props()
</script>

<div id="invite-shell" class="min-h-[calc(100dvh-3.5rem)] bg-[#0b0d0e] px-4 py-10 text-stone-100 sm:px-6 sm:py-16">
  <main class="mx-auto grid max-w-5xl overflow-hidden border border-white/10 bg-[#121617] lg:grid-cols-[0.9fr_1.1fr]">
    <div class="relative min-h-72 overflow-hidden border-b border-white/10 lg:min-h-[36rem] lg:border-b-0 lg:border-r">
      <svg
        id="invite-graphic"
        class="absolute inset-0 size-full"
        viewBox="0 0 520 620"
        preserveAspectRatio="xMidYMid slice"
        role="img"
        aria-labelledby="invite-graphic-title invite-graphic-desc"
      >
        <title id="invite-graphic-title">Sealed investigation file</title>
        <desc id="invite-graphic-desc">An original graphic of a sealed case envelope over a city grid.</desc>
        <defs>
          <pattern id="invite-grid" width="26" height="26" patternUnits="userSpaceOnUse">
            <path d="M26 0H0V26" fill="none" stroke="#303637" stroke-width="1" />
          </pattern>
        </defs>
        <rect width="520" height="620" fill="#101415" />
        <rect width="520" height="620" fill="url(#invite-grid)" opacity="0.75" />
        <path d="M-30 475C120 382 282 450 558 302" fill="none" stroke="#3f4647" stroke-width="16" opacity="0.7" />
        <path d="M-30 475C120 382 282 450 558 302" fill="none" stroke="#8a8d87" stroke-width="2" stroke-dasharray="10 12" />
        <g transform="translate(66 152) rotate(-5)">
          <rect width="388" height="258" fill="#d8d1c4" />
          <path d="M0 0l194 132L388 0M0 258l144-116M388 258L244 142" fill="none" stroke="#918a7d" stroke-width="3" />
          <circle cx="194" cy="132" r="44" fill="#b84b40" />
          <circle cx="194" cy="132" r="29" fill="none" stroke="#772e29" stroke-width="3" />
          <text x="194" y="138" text-anchor="middle" fill="#f0ddd2" font-family="ui-monospace, monospace" font-size="13" font-weight="700">SEALED</text>
        </g>
      </svg>
    </div>

    <section class="flex flex-col justify-center px-6 py-10 sm:px-10 lg:px-14" aria-labelledby="invite-title">
      {#if invite}
        <p class="font-mono text-xs uppercase tracking-[0.2em] text-[#e06a5b]">Invitation · {invite.room_code}</p>
        <h1 id="invite-title" class="mt-4 font-serif text-3xl font-semibold tracking-[-0.035em] text-stone-100 sm:text-4xl">
          {invite.game_title}
        </h1>
        <p class="mt-3 text-base text-stone-400">{invite.case_title}</p>

        <dl id="invite-room-details" class="mt-8 divide-y divide-white/10 border-y border-white/10 text-sm">
          <div class="flex justify-between gap-6 py-4">
            <dt class="text-stone-500">Host</dt>
            <dd class="text-right font-medium text-stone-200">{invite.host_name}</dd>
          </div>
          <div class="flex justify-between gap-6 py-4">
            <dt class="text-stone-500">Detectives</dt>
            <dd class="font-mono text-stone-200">{invite.detective_count}/{invite.max_detectives}</dd>
          </div>
          <div class="flex justify-between gap-6 py-4">
            <dt class="text-stone-500">Places left</dt>
            <dd class="font-mono text-stone-200">{invite.places_left}</dd>
          </div>
        </dl>

        {#if error}
          <p id="invite-error" role="alert" class="mt-6 border-l-2 border-red-500 bg-red-950/30 px-4 py-3 text-sm text-red-200">
            {error}
          </p>
        {/if}

        <button
          id="accept-game-invite"
          type="button"
          phx-click="accept_invite"
          class="mt-8 cursor-pointer bg-[#e06a5b] px-5 py-3 text-sm font-semibold text-[#0b0d0e] transition hover:bg-[#ef7a6a] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#e06a5b]"
        >
          {invite.membership_status === "active" ? "Return to room" : "Join as detective"}
        </button>
        <p class="mt-3 text-xs leading-5 text-stone-500">Membership is added only after confirmation.</p>
      {:else}
        <p class="font-mono text-xs uppercase tracking-[0.2em] text-[#e06a5b]">Invitation unavailable</p>
        <h1 id="invite-title" class="mt-4 font-serif text-3xl font-semibold tracking-tight">This file is closed.</h1>
        <p id="invite-error" role="alert" class="mt-5 text-sm leading-6 text-stone-400">
          {error ?? "This invitation cannot be used."}
        </p>
        <a
          id="invite-back-dashboard"
          href="/dashboard"
          class="mt-8 inline-flex w-fit border border-white/15 px-4 py-2.5 text-sm font-semibold text-stone-200 transition hover:border-[#e06a5b] hover:text-[#e06a5b]"
        >
          Back to dashboard
        </a>
      {/if}
    </section>
  </main>
</div>
