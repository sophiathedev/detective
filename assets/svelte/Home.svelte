<script>
  let { app_name, count, phoenix_version, live_svelte_version } = $props()
</script>

<div id="home-svelte" class="min-h-screen bg-stone-50 text-zinc-950">
  <header class="border-b border-zinc-200 bg-stone-50/95">
    <div class="mx-auto flex h-16 max-w-7xl items-center justify-between px-6 lg:px-8">
      <a href="/" class="text-base font-semibold tracking-tight transition hover:text-emerald-700">
        {app_name}
      </a>
      <nav class="flex items-center gap-1" aria-label="Resources">
        <a
          href="https://hexdocs.pm/live_svelte/"
          class="rounded-md px-3 py-2 text-sm text-zinc-600 transition hover:bg-zinc-200/60 hover:text-zinc-950"
        >
          LiveSvelte docs
        </a>
        <a
          href="https://tailwindcss.com/docs"
          class="rounded-md px-3 py-2 text-sm text-zinc-600 transition hover:bg-zinc-200/60 hover:text-zinc-950"
        >
          Tailwind docs
        </a>
      </nav>
    </div>
  </header>

  <main class="mx-auto grid max-w-7xl gap-16 px-6 py-20 lg:grid-cols-[minmax(0,1fr)_24rem] lg:px-8 lg:py-28">
    <section class="max-w-3xl">
      <p class="font-mono text-sm text-emerald-700">Phoenix / LiveSvelte / Tailwind CSS</p>
      <h1 class="mt-6 text-5xl font-semibold tracking-[-0.045em] text-balance sm:text-7xl">
        Phoenix data.<br />Svelte interface.
      </h1>
      <p class="mt-8 max-w-2xl text-lg leading-8 text-zinc-600">
        LiveSvelte now owns the primary interface. Phoenix keeps server state and realtime transport;
        Svelte renders the product experience; Tailwind CSS supplies the design system.
      </p>

      <div class="mt-12 flex flex-wrap gap-3">
        <a
          href="https://hexdocs.pm/live_svelte/basic_usage.html"
          class="inline-flex items-center rounded-lg bg-zinc-950 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700"
        >
          Build first screen
        </a>
        <a
          href="https://hexdocs.pm/phoenix_live_view/"
          class="inline-flex items-center rounded-lg border border-zinc-300 bg-transparent px-4 py-2.5 text-sm font-semibold text-zinc-800 transition hover:border-zinc-400 hover:bg-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-zinc-500"
        >
          LiveView reference
        </a>
      </div>
    </section>

    <aside class="border-t border-zinc-300 pt-8 lg:border-l lg:border-t-0 lg:pl-10 lg:pt-0">
      <h2 class="text-sm font-semibold text-zinc-950">Server round trip</h2>
      <p class="mt-2 text-sm leading-6 text-zinc-600">
        Buttons send LiveView events. Updated count returns through LiveSvelte props.
      </p>

      <div class="mt-8 flex items-center gap-5">
        <button
          id="decrement-count"
          type="button"
          phx-click="decrement"
          aria-label="Decrease count"
          class="flex size-11 cursor-pointer items-center justify-center rounded-lg border border-zinc-300 bg-white text-xl transition hover:border-zinc-500 hover:bg-zinc-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-zinc-500"
        >
          −
        </button>
        <output id="server-count" class="min-w-12 text-center font-mono text-4xl font-semibold" aria-live="polite">
          {count}
        </output>
        <button
          id="increment-count"
          type="button"
          phx-click="increment"
          aria-label="Increase count"
          class="flex size-11 cursor-pointer items-center justify-center rounded-lg bg-zinc-950 text-xl text-white transition hover:bg-emerald-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700"
        >
          +
        </button>
      </div>

      <dl class="mt-12 space-y-4 border-t border-zinc-300 pt-6 text-sm">
        <div class="flex items-center justify-between gap-4">
          <dt class="text-zinc-500">Phoenix</dt>
          <dd class="font-mono text-zinc-800">v{phoenix_version}</dd>
        </div>
        <div class="flex items-center justify-between gap-4">
          <dt class="text-zinc-500">LiveSvelte</dt>
          <dd class="font-mono text-zinc-800">v{live_svelte_version}</dd>
        </div>
        <div class="flex items-center justify-between gap-4">
          <dt class="text-zinc-500">Tailwind CSS</dt>
          <dd class="font-mono text-zinc-800">v4</dd>
        </div>
      </dl>
    </aside>
  </main>
</div>
