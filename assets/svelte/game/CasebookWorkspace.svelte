<script>
  let { page = "history", view, actions = {} } = $props()

  let availableActions = $derived(new Set(view?.availableActions ?? []))
  let search = $derived(view?.search ?? {})
  let question = $derived(view?.question ?? {})
  let evidence = $derived(view?.evidence ?? {})
  let accusation = $derived(view?.accusation ?? {})
  let history = $derived(view?.history ?? {})
  let accusationConfirming = $state(false)
  let selectedInterrogation = $derived(
    (question.interrogationOptions ?? []).find(
      (option) => option.suspect_id === question.selectedSuspectId,
    ),
  )
  let selectedTopic = $derived(
    selectedInterrogation?.topics?.find((topic) => topic.id === question.selectedTopicId),
  )
  let selectedAccusationSuspect = $derived(
    (accusation.options?.suspects ?? []).find(
      (suspect) => suspect.id === accusation.selectedSuspectId,
    ),
  )
  let selectedAccusationWeapon = $derived(
    (accusation.options?.weapons ?? []).find(
      (weapon) => weapon.id === accusation.selectedWeaponId,
    ),
  )
  let selectedAccusationMotive = $derived(
    (accusation.options?.motives ?? []).find(
      (motive) => motive.id === accusation.selectedMotiveId,
    ),
  )
  let finalGuessFiledCount = $derived(
    (view?.detectives ?? []).filter((detective) => detective.final_guess_submitted).length,
  )

  function toggleBlockedPlayer(playerId, checked) {
    const selected = new Set(question.blockedSnitchPlayerIds ?? [])
    if (checked) selected.add(playerId)
    else selected.delete(playerId)
    actions.setBlockedSnitchPlayers?.([...selected])
  }

  function caseCardLabel(cardId) {
    const card = (evidence.knownCaseCards ?? []).find((candidate) => candidate.id === cardId)
    return card ? `${card.code} ${card.title}` : cardId
  }

  function setAccusationSelection(action, value) {
    accusationConfirming = false
    action?.(value)
  }

  function confirmAccusation() {
    accusationConfirming = false
    actions.submitAccusation?.()
  }
</script>

{#if page === "search"}
  <section id="casebook-action-page" class="casebook-workspace-page p-4 sm:p-5" aria-labelledby="casebook-search-heading">
    <div class="flex flex-wrap items-start justify-between gap-4 border-b border-[#a38b6e] pb-4">
      <div>
        <p class="font-mono text-[10px] uppercase tracking-[0.18em] text-[#8c3f33]">Action ledger</p>
        <h2 id="casebook-search-heading" class="mt-1 font-serif text-2xl font-semibold text-[#2e241c]">
          {view.activeDetective?.display_name ?? "Field search"}
        </h2>
        <p class="mt-1 text-sm text-[#695642]">
          {view.role === "detective" && view.ownPlayer?.id === view.activeDetective?.id
            ? "Your turn. Choose an authorized subject, then file the Search command."
            : "Observing the active Detective's turn."}
        </p>
      </div>
      {#if view.role === "detective"}
        <dl class="text-right">
          <dt class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#80694f]">Actions</dt>
          <dd class="mt-1 font-mono text-lg font-semibold">{view.ownPlayer?.actions_remaining ?? 0}</dd>
        </dl>
      {/if}
    </div>

    {#if view.role === "detective"}
      <section
        id="current-location-search"
        class="mt-5 border-l-4 border-[#71372f] bg-[#eadbbc] p-4"
        aria-labelledby="current-location-search-heading"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">
              Current location
            </p>
            <h3
              id="current-location-search-heading"
              class="mt-1 font-serif text-lg font-semibold text-[#2e241c]"
            >
              {search.currentLocation?.name ?? "Placement required"}
            </h3>
            <p class="mt-1 max-w-xl text-xs leading-5 text-[#695642]">
              Search card text remains private. Revealed Case cards enter your casebook; taken
              evidence returns faceup after three Day advances.
            </p>
          </div>
          <span class="border border-[#806749] px-2 py-1 font-mono text-[9px] uppercase text-[#725e48]">
            1 AP
          </span>
        </div>

        <button
          id="casebook-submit-location-search"
          type="button"
          disabled={!availableActions.has("search_location") || !search.currentLocation}
          onclick={() => actions.submitLocationSearch?.()}
          class="mt-3 min-h-11 w-full cursor-pointer bg-[#30261f] px-4 text-left text-sm font-semibold text-[#f5e7c9] transition hover:bg-[#49372a] active:translate-y-px disabled:cursor-not-allowed disabled:opacity-40"
        >
          Search {search.currentLocation?.name ?? "current location"}
          <span class="float-right font-mono text-[10px]">
            {availableActions.has("search_location") ? "CONFIRM" : "UNAVAILABLE"}
          </span>
        </button>
      </section>
    {/if}

    <fieldset id="casebook-search-subjects" class="mt-5">
      <legend class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#80694f]">Known persons</legend>
      <div class="mt-2 grid gap-2 sm:grid-cols-2">
        {#each search.suspects ?? [] as suspect}
          {@const authorized = (search.searchableSuspectIds ?? []).includes(suspect.id) || (search.interrogatableSuspectIds ?? []).includes(suspect.id)}
          <button
            id={`casebook-suspect-${suspect.id}`}
            type="button"
            disabled={!authorized}
            aria-pressed={search.selectedSuspectId === suspect.id}
            onclick={() => actions.selectSuspect?.(suspect.id)}
            class={`min-h-14 border p-3 text-left transition ${search.selectedSuspectId === suspect.id ? "border-[#8f342d] bg-[#f0dfbd] ring-2 ring-[#a54235]" : "border-[#a18a6d] bg-[#e6d9bd]"} ${authorized ? "cursor-pointer hover:bg-[#f2e4c8]" : "cursor-default opacity-55"}`}
          >
            <span class="block font-serif text-sm font-semibold">{suspect.name}</span>
            <span class="mt-1 block font-mono text-[8px] uppercase tracking-[0.08em] text-[#705b45]">
              {suspect.occupation ?? "Person of interest"}{suspect.location_name ? ` · ${suspect.location_name}` : ""}
            </span>
          </button>
        {:else}
          <p class="casebook-empty-page">No known subject can be searched yet.</p>
        {/each}
      </div>
    </fieldset>

    <button
      id="casebook-submit-suspect-search"
      type="button"
      disabled={!availableActions.has("search_suspect") || !(search.searchableSuspectIds ?? []).includes(search.selectedSuspectId)}
      onclick={() => actions.submitSuspectSearch?.()}
      class="mt-4 min-h-11 w-full cursor-pointer bg-[#30261f] px-4 text-left text-sm font-semibold text-[#f5e7c9] transition hover:bg-[#49372a] disabled:cursor-not-allowed disabled:opacity-40"
    >Search selected suspect <span class="float-right font-mono text-[10px]">1 AP</span></button>
  </section>

{:else if page === "question"}
  <section
    id="interrogation-workspace"
    class="casebook-workspace-page border-y border-[#91785c] bg-[#dccdad] p-4 sm:p-5"
    aria-labelledby="interrogation-heading"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">ARC interview desk</p>
        <h3 id="interrogation-heading" class="mt-1 font-serif text-xl font-semibold">Suspect statement</h3>
      </div>
      <p id="interrogation-status" class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]" aria-live="polite">
        {view.phase?.replaceAll("_", " ")}
      </p>
    </div>

    {#if view.phase === "detective_turn" && availableActions.has("interrogate")}
      {#if question.latestStatement}
        <div id="challenge-result" class="mt-4 border-l-4 border-[#8c3f33] bg-[#eadbbc] p-4" aria-live="polite">
          <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7d6650]">Latest private note · {question.latestStatement.topic_code}</p>
          <p class="mt-2 font-serif text-sm italic leading-6">“{question.latestStatement.response_text}”</p>
          <p class="mt-2 font-mono text-[9px] uppercase tracking-[0.1em] text-[#8c3f33]">{question.latestStatement.resolution.replaceAll("_", " ")}</p>
        </div>
      {/if}

      <fieldset id="interrogation-subjects" class="mt-4">
        <legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7b654d]">
          Suspects at your location
        </legend>
        <div class="mt-2 grid gap-2 sm:grid-cols-2">
          {#each question.interrogationOptions ?? [] as interrogation}
            <button
              id={`casebook-question-suspect-${interrogation.suspect_id}`}
              type="button"
              aria-pressed={question.selectedSuspectId === interrogation.suspect_id}
              onclick={() => actions.selectSuspect?.(interrogation.suspect_id)}
              class={`min-h-12 cursor-pointer border px-3 py-2 text-left transition active:translate-y-px ${question.selectedSuspectId === interrogation.suspect_id ? "border-[#963a31] bg-[#f1e2c4] ring-2 ring-[#a54235]" : "border-[#9f896c] bg-[#e4d6b8] hover:bg-[#ecdec1]"}`}
            >
              <span class="block font-serif text-sm font-semibold">
                {interrogation.suspect_name}
              </span>
              <span class="mt-1 block font-mono text-[8px] uppercase tracking-[0.08em] text-[#705b45]">
                {interrogation.topics?.length ?? 0} known case cards
              </span>
            </button>
          {/each}
        </div>
      </fieldset>

      {#if selectedInterrogation}
        <div class="mt-4 grid gap-4 sm:grid-cols-[0.8fr_1.2fr]">
          <div class="border-l-2 border-[#9e4035] pl-3">
            <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7b654d]">Subject</p>
            <p class="mt-1 font-serif text-lg font-semibold">{selectedInterrogation.suspect_name}</p>
            <p class="mt-2 text-xs leading-5 text-[#695642]">Choose one known case card. Free-form questions are not legal commands.</p>
          </div>

          <fieldset id="interrogation-topics">
            <legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7b654d]">Known topics</legend>
            <div class="mt-2 grid gap-2">
              {#each selectedInterrogation.topics ?? [] as topic}
                <label id={`interrogate-topic-${topic.id}`} class={`flex min-h-11 cursor-pointer items-center gap-3 border px-3 py-2 transition ${question.selectedTopicId === topic.id ? "border-[#963a31] bg-[#f1e2c4]" : "border-[#9f896c] bg-[#e4d6b8] hover:bg-[#ecdec1]"}`}>
                  <input type="radio" name="interrogation-topic" value={topic.id} checked={question.selectedTopicId === topic.id} onchange={() => actions.selectTopic?.(topic.id)} class="accent-[#963a31]" />
                  <span class="font-mono text-[10px] font-semibold text-[#963a31]">{topic.code}</span>
                  <span class="text-sm font-semibold">{topic.title}</span>
                </label>
              {/each}
            </div>
          </fieldset>
        </div>

        {#if question.selectedSuspectLeverage > 0}
          <label class="mt-4 flex min-h-11 cursor-pointer items-center gap-3 border-t border-[#a48b6c] pt-3 text-xs">
            <input type="checkbox" checked={question.spendLeverage} onchange={(event) => actions.setSpendLeverage?.(event.currentTarget.checked)} class="accent-[#963a31]" />
            Spend 1 leverage over this suspect to force the most useful response.
          </label>
        {/if}

        <button id="casebook-submit-interrogation" type="button" disabled={!selectedTopic} onclick={() => actions.submitInterrogation?.()} class="mt-4 min-h-11 w-full cursor-pointer bg-[#30261f] px-4 text-left text-sm font-semibold text-[#f5e7c9] transition hover:bg-[#49372a] disabled:cursor-not-allowed disabled:opacity-40">
          Question suspect <span class="float-right font-mono text-[10px]">{question.freeQuestionSuspectId === question.selectedSuspectId ? "FREE" : "1 AP"}</span>
        </button>
      {:else}
        <p class="mt-4 border-l-2 border-[#9e4035] pl-3 text-sm leading-6 text-[#65523f]">Select an authorized suspect from the Search folio. You must share their location.</p>
      {/if}

    {:else if question.pendingPublic?.stage === "awaiting_chisel_block"}
      {#if view.role === "chisel" && view.chisel?.pendingInterrogation}
        <div id="chisel-block-decision" class="mt-4 border-l-4 border-[#71372f] bg-[#d3c19f] p-4">
          <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">Chisel leverage window</p>
          <p class="mt-2 text-sm leading-6 text-[#5f4b39]">{view.chisel.pendingInterrogation.detective.display_name} asks {view.chisel.pendingInterrogation.suspect.name} about case card {view.chisel.pendingInterrogation.topic.code}.</p>
          <div class="mt-3 grid gap-2 sm:grid-cols-2">
            <button id="casebook-allow-question" type="button" disabled={!availableActions.has("allow_question")} onclick={() => actions.allowQuestion?.()} class="min-h-11 cursor-pointer border-2 border-[#344a40] bg-[#d6d2b5] px-3 text-sm font-semibold text-[#263c34] disabled:cursor-not-allowed disabled:opacity-40">Allow question</button>
            <button id="casebook-block-question" type="button" disabled={!availableActions.has("block_question")} onclick={() => actions.blockQuestion?.()} class="min-h-11 cursor-pointer border-2 border-[#9b3d34] bg-[#e1c5a9] px-3 text-sm font-semibold text-[#812f29] disabled:cursor-not-allowed disabled:opacity-40">Spend matching leverage to block</button>
          </div>
        </div>
      {:else}
        <p class="casebook-empty-page">Question under review · waiting for the Chisel's leverage decision.</p>
      {/if}

    {:else if question.pendingPublic?.stage === "question_blocked"}
      <div id="blocked-question-card" class="mt-4 border-l-4 border-[#9b3d34] bg-[#e1c5a9] p-4">
        <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#812f29]">Question blocked</p>
        <p class="mt-2 text-sm leading-6 text-[#5f4b39]">The action remains spent. The questioning Detective may abandon the question or pay $2 Scratch to bribe the goon.</p>
        {#if availableActions.has("accept_question_block") || availableActions.has("bribe_goon")}
          <div class="mt-3 grid gap-2 sm:grid-cols-2">
            <button id="casebook-accept-question-block" type="button" disabled={!availableActions.has("accept_question_block")} onclick={() => actions.acceptQuestionBlock?.()} class="min-h-11 cursor-pointer border border-[#796349] bg-[#d7c7aa] px-3 text-sm font-semibold disabled:cursor-not-allowed disabled:opacity-40">Abandon question</button>
            <button id="casebook-bribe-goon" type="button" disabled={!availableActions.has("bribe_goon")} onclick={() => actions.bribeGoon?.()} class="min-h-11 cursor-pointer bg-[#8f372f] px-3 text-sm font-semibold text-[#fff0d6] disabled:cursor-not-allowed disabled:opacity-40">Pay $2 and proceed</button>
          </div>
        {/if}
      </div>

    {:else if question.pendingPublic?.stage === "awaiting_snitches"}
      <div id="snitch-window" class="mt-4 border-y border-[#8e765b] bg-[#d3c19f] p-4">
        <div class="flex items-center justify-between gap-3">
          <div><p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#812f29]">Facedown informants</p><p class="mt-1 font-serif text-lg font-semibold">Snitch window</p></div>
          <p class="font-mono text-[9px] uppercase tracking-[0.1em] text-[#725e48]">{question.pendingPublic.snitch_decisions_recorded}/{question.pendingPublic.snitch_decisions_required} filed</p>
        </div>
        {#if availableActions.has("choose_snitch") || availableActions.has("decline_snitch")}
          <p class="mt-3 text-sm leading-6 text-[#5f4b39]">Your choice remains hidden until every eligible Detective files a marker. An allowed Snitch costs $3 only after the final response.</p>
          <div class="mt-3 grid grid-cols-2 gap-2">
            <button id="casebook-decline-snitch" type="button" disabled={!availableActions.has("decline_snitch")} onclick={() => actions.declineSnitch?.()} class="min-h-11 cursor-pointer border border-[#796349] bg-[#d7c7aa] px-3 text-sm font-semibold disabled:opacity-40">Pass</button>
            <button id="casebook-choose-snitch" type="button" disabled={!availableActions.has("choose_snitch")} onclick={() => actions.chooseSnitch?.()} class="min-h-11 cursor-pointer bg-[#30261f] px-3 text-sm font-semibold text-[#f5e7c9] disabled:opacity-40">Place Snitch facedown</button>
          </div>
        {:else}
          <p class="mt-3 text-sm leading-6 text-[#5f4b39]">Waiting for all eligible Detectives to lock their private choice.</p>
        {/if}
      </div>

    {:else if question.pendingPublic?.stage === "awaiting_chisel_snitch_block"}
      {#if view.role === "chisel" && view.chisel?.pendingInterrogation}
        <div id="chisel-snitch-blocks" class="mt-4 border-l-4 border-[#71372f] bg-[#d3c19f] p-4">
          <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">Revealed Snitch markers</p>
          <p class="mt-2 text-sm leading-6 text-[#5f4b39]">Spend one matching leverage marker for each informant you want to block.</p>
          <fieldset class="mt-3 grid gap-2">
            <legend class="sr-only">Choose Snitches to block</legend>
            {#each view.chisel.pendingInterrogation.snitch_requests ?? [] as request}
              <label id={`snitch-block-${request.player_id}`} class="flex min-h-11 cursor-pointer items-center justify-between gap-3 border border-[#8e765b] bg-[#e5d6b8] px-3 py-2">
                <span class="text-sm font-semibold">{request.display_name}</span>
                <span class="flex items-center gap-2 font-mono text-[9px] uppercase text-[#725e48]">
                  {request.can_block ? "block" : "no leverage"}
                  <input type="checkbox" checked={(question.blockedSnitchPlayerIds ?? []).includes(request.player_id)} disabled={!request.can_block} onchange={(event) => toggleBlockedPlayer(request.player_id, event.currentTarget.checked)} class="accent-[#963a31]" />
                </span>
              </label>
            {/each}
          </fieldset>
          <button id="casebook-resolve-snitches" type="button" disabled={!availableActions.has("resolve_snitches")} onclick={() => actions.submitSnitchResolution?.()} class="mt-3 min-h-11 w-full cursor-pointer bg-[#8f372f] px-4 text-sm font-semibold text-[#fff0d6] disabled:opacity-40">Resolve Snitches and open response deck</button>
        </div>
      {:else}
        <p class="casebook-empty-page">Snitch markers revealed · waiting for the Chisel.</p>
      {/if}

    {:else if question.pendingPublic?.stage === "awaiting_chisel_response"}
      {#if view.role === "chisel" && view.chisel?.pendingInterrogation}
        <div id="chisel-response-deck" class="mt-4">
          <p class="text-sm leading-6 text-[#5f4b39]">{view.chisel.pendingInterrogation.detective.display_name} asks {view.chisel.pendingInterrogation.suspect.name} about case card {view.chisel.pendingInterrogation.topic.code}.</p>
          <fieldset class="mt-3">
            <legend class="sr-only">Choose the suspect response</legend>
            <div class="grid gap-2">
              {#each view.chisel.pendingInterrogation.response_options ?? [] as response}
                <label id={`chisel-response-${response.id}`} class={`cursor-pointer border-l-4 px-3 py-3 transition ${question.selectedResponseId === response.id ? "bg-[#f3e4c5]" : "bg-[#d2c09f] hover:bg-[#dfcead]"} ${response.type === "most_useful" ? "border-[#2f4b42]" : "border-[#9d3d34]"}`}>
                  <span class="flex items-center justify-between gap-3"><span class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#6f5944]">{response.type.replaceAll("_", " ")}</span><input type="radio" name="chisel-response" value={response.id} checked={question.selectedResponseId === response.id} onchange={() => actions.selectResponse?.(response.id)} class="accent-[#963a31]" /></span>
                  <span class="mt-2 block font-serif text-sm leading-6">{response.text}</span>
                </label>
              {/each}
            </div>
          </fieldset>
          <button id="casebook-submit-response" type="button" disabled={!question.selectedResponseId} onclick={() => actions.submitResponse?.()} class="mt-3 min-h-11 w-full cursor-pointer bg-[#8f372f] px-4 text-sm font-semibold text-[#fff0d6] disabled:opacity-40">Seal and deliver response</button>
        </div>
      {:else}
        <p class="casebook-empty-page">Statement requested · waiting for the Chisel to seal a response.</p>
      {/if}

    {:else if question.pendingPublic?.stage === "awaiting_detective_decision"}
      <div id="published-response-card" class="relative mt-4 border border-[#806749] bg-[#efe0c0] p-4" tabindex="-1">
        <span class="absolute right-3 top-3 font-mono text-[9px] uppercase tracking-[0.12em] text-[#963a31]">Statement · {question.pendingPublic.topic_code}</span>
        {#if view.role === "detective" && question.pendingPrivate?.response_text}
          <p class="max-w-xl pr-20 font-serif text-base italic leading-7">“{question.pendingPrivate.response_text}”</p>
        {:else if view.role === "chisel" && view.chisel?.pendingInterrogation?.selected_response}
          <p class="max-w-xl pr-20 font-serif text-base italic leading-7">“{view.chisel.pendingInterrogation.selected_response.text}”</p>
        {:else}
          <p class="max-w-xl pr-20 font-serif text-base italic leading-7 text-[#76624c]">The statement is sealed for the questioning Detective.</p>
        {/if}
      </div>
      {#if availableActions.has("accept_response") || availableActions.has("challenge_response")}
        <div class="mt-3 grid grid-cols-2 gap-2">
          <button id="casebook-accept-response" type="button" disabled={!availableActions.has("accept_response")} onclick={() => actions.acceptResponse?.()} class="min-h-12 cursor-pointer border-2 border-[#344a40] bg-[#d6d2b5] font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-[#263c34] disabled:opacity-40">Accept statement</button>
          <button id="casebook-challenge-response" type="button" disabled={!availableActions.has("challenge_response")} onclick={() => actions.challengeResponse?.()} class="min-h-12 cursor-pointer border-2 border-[#9b3d34] bg-[#e1c5a9] font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-[#812f29] disabled:opacity-40">Challenge · stake 1</button>
        </div>
      {/if}
    {:else if question.latestStatement}
      <div id="challenge-result" class="mt-4 border-l-4 border-[#8c3f33] bg-[#eadbbc] p-4" aria-live="polite">
        <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#7d6650]">Latest private note · {question.latestStatement.topic_code}</p>
        <p class="mt-2 font-serif text-sm italic leading-6">“{question.latestStatement.response_text}”</p>
        <p class="mt-2 font-mono text-[9px] uppercase tracking-[0.1em] text-[#8c3f33]">{question.latestStatement.resolution.replaceAll("_", " ")}</p>
      </div>
    {:else}
      <p class="casebook-empty-page">Move to a suspect, choose a known case card, and spend one action to question them.</p>
    {/if}
  </section>

{:else if page === "evidence"}
  {#if view.role === "detective"}
    <section id="private-evidence-dossier" class="casebook-workspace-page border-y border-[#91785c] bg-[#d4c3a3] p-4 sm:p-5" aria-labelledby="evidence-dossier-heading">
      <div class="flex flex-wrap items-end justify-between gap-3">
        <div><p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Private folio</p><h3 id="evidence-dossier-heading" class="mt-1 font-serif text-xl font-semibold">Search notes and evidence</h3></div>
        <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#705b45]">{evidence.heldEvidence?.length ?? 0} held / {evidence.knownCaseCards?.length ?? 0} known</p>
      </div>
      <div class="mt-4 grid gap-3 sm:grid-cols-[minmax(0,1.1fr)_minmax(12rem,0.9fr)]">
        <div id="search-note-ledger" class="grid content-start gap-3">
          {#each evidence.searchNotes ?? [] as note, index}
            <article
              id={`search-note-${index}`}
              data-search-note={index}
              class="border-l-4 border-[#71372f] bg-[#eadbbc] p-3"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">
                  Day {note.day} / {note.target_type.replaceAll("_", " ")}
                </p>
                <span class="font-mono text-[8px] uppercase tracking-[0.1em] text-[#8c3f33]">
                  {index === 0 ? "latest filing" : "archived"}
                </span>
              </div>
              <p class="mt-2 font-serif text-sm italic leading-6">“{note.text}”</p>

              {#if (note.case_card_ids?.length ?? 0) > 0}
                <ul class="mt-3 grid gap-1 border-t border-[#b19b7b] pt-2">
                  {#each note.case_card_ids as cardId}
                    <li class="font-mono text-[9px] uppercase tracking-[0.08em] text-[#6b5844]">
                      Revealed: {caseCardLabel(cardId)}
                    </li>
                  {/each}
                </ul>
              {/if}

              {#if (note.taken_case_card_ids?.length ?? 0) > 0}
                <ul class="mt-2 grid gap-1">
                  {#each note.taken_case_card_ids as cardId}
                    <li class="font-mono text-[9px] uppercase tracking-[0.08em] text-[#8c3f33]">
                      Evidence held: {caseCardLabel(cardId)}
                    </li>
                  {/each}
                </ul>
              {/if}
            </article>
          {:else}
            <p class="casebook-empty-page">No private Search card has been filed.</p>
          {/each}
        </div>
        <div id="held-evidence-list" class="grid content-start gap-2">
          {#each evidence.heldEvidence ?? [] as card}
            <article id={`held-evidence-${card.id}`} class="border border-[#8b7257] bg-[#efe0c0] px-3 py-2"><div class="flex items-center justify-between gap-3"><span class="font-mono text-[10px] font-semibold text-[#8c3f33]">{card.code}</span><span class="font-mono text-[8px] uppercase tracking-[0.1em] text-[#725e48]">held evidence</span></div><h4 class="mt-1 font-serif text-sm font-semibold">{card.title}</h4>{#if card.description}<p class="mt-1 text-[11px] leading-4 text-[#695642]">{card.description}</p>{/if}</article>
          {:else}<p class="casebook-empty-page">No Case card is currently held as evidence.</p>{/each}
        </div>
      </div>
    </section>
  {:else}
    <p id="evidence-private-seal" class="casebook-empty-page">Detective evidence stays sealed on each private user channel.</p>
  {/if}

{:else if page === "accusation"}
  {#if view.result}
    <section id="case-closed-result" class="casebook-workspace-page border-2 border-[#71372f] bg-[#eadbbc] p-4 sm:p-5" aria-labelledby="case-result-heading">
      <div class="flex flex-wrap items-start justify-between gap-4 border-b border-[#9d8669] pb-4"><div><p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Case closed</p><h3 id="case-result-heading" class="mt-1 font-serif text-2xl font-semibold">The sealed solution</h3></div><p class="font-mono text-[10px] uppercase tracking-[0.12em] text-[#71372f]">Winner: {view.result.winner.role}</p></div>
      <dl class="mt-4 grid gap-3 sm:grid-cols-3"><div class="border-l-2 border-[#71372f] pl-3"><dt class="font-mono text-[9px] uppercase text-[#725e48]">Suspect</dt><dd class="mt-1 font-serif text-base font-semibold">{view.result.solution.suspect_name}</dd></div><div class="border-l-2 border-[#71372f] pl-3"><dt class="font-mono text-[9px] uppercase text-[#725e48]">Weapon</dt><dd class="mt-1 font-serif text-base font-semibold">{view.result.solution.weapon_label}</dd></div><div class="border-l-2 border-[#71372f] pl-3"><dt class="font-mono text-[9px] uppercase text-[#725e48]">Motive</dt><dd class="mt-1 font-serif text-base font-semibold">{view.result.solution.motive_label}</dd></div></dl>
      {#if view.result.epilogue}<p class="mt-4 max-w-3xl font-serif text-sm italic leading-6 text-[#4f3e30]">{view.result.epilogue}</p>{/if}
    </section>
  {:else if view.role === "detective" && (accusation.options?.motives?.length ?? 0) > 0 && (availableActions.has("accuse") || availableActions.has("submit_final_guess") || accusation.solveAttempt || accusation.finalGuess || view.phase === "accusation")}
    <section id="accusation-sheet" class="casebook-workspace-page border-2 border-[#71372f] bg-[#d7c6a6] p-4 sm:p-5" aria-labelledby="accusation-heading">
      <div class="flex flex-wrap items-start justify-between gap-3"><div><p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Sealed deduction</p><h3 id="accusation-heading" class="mt-1 font-serif text-xl font-semibold">Suspect, weapon, motive</h3></div><span class="border border-[#8c3f33] px-2 py-1 font-mono text-[9px] uppercase tracking-[0.1em] text-[#8c3f33]">{view.phase === "accusation" ? "final guess" : "solve token"}</span></div>

      {#if view.phase === "accusation"}
        <section id="final-guess-progress" class="mt-4 border-y border-[#9d8669] py-3" aria-labelledby="final-guess-progress-heading" aria-live="polite">
          <div class="flex items-center justify-between gap-3">
            <h4 id="final-guess-progress-heading" class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">Sealed envelopes</h4>
            <span class="font-mono text-[9px] font-semibold uppercase text-[#8c3f33]">{finalGuessFiledCount} / {view.detectives?.length ?? 0} filed</span>
          </div>
          <ul class="mt-2 grid gap-2 sm:grid-cols-2">
            {#each view.detectives ?? [] as detective}
              <li id={`final-guess-player-${detective.id}`} class="flex min-h-10 items-center justify-between border border-[#9d8669] bg-[#e4d6b8] px-3 text-sm">
                <span class="font-serif font-semibold">{detective.display_name}</span>
                <span class={`font-mono text-[9px] font-semibold uppercase tracking-[0.1em] ${detective.final_guess_submitted ? "text-[#315046]" : "text-[#8c3f33]"}`}>
                  {detective.final_guess_submitted ? "FILED" : "PENDING"}
                </span>
              </li>
            {/each}
          </ul>
        </section>
      {/if}

      {#if accusation.solveAttempt}<p id="solve-attempt-result" class="mt-3 border-l-4 border-[#8c3f33] bg-[#eadbbc] p-3 text-sm font-semibold">{accusation.solveAttempt.correct_count} of 3 elements were correct. The token is spent; your turn continues.</p>{/if}
      {#if accusation.finalGuess && view.phase === "accusation"}
        <p id="final-guess-sealed" class="mt-3 border border-dashed border-[#8e765b] p-4 text-center font-serif text-sm italic">Your final guess is sealed. Waiting for the remaining Detectives.</p>
      {:else}
        <div class="mt-4 grid gap-4 lg:grid-cols-3">
          <fieldset id="accusation-suspects"><legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">1 / Suspect</legend><div class="mt-2 grid gap-2">{#each accusation.options?.suspects ?? [] as suspect}<label class={`flex min-h-11 cursor-pointer items-center gap-3 border px-3 py-2 ${accusation.selectedSuspectId === suspect.id ? "border-[#8c3f33] bg-[#f0dfbd]" : "border-[#9d8669] bg-[#e4d6b8]"}`}><input type="radio" name="accusation-suspect" value={suspect.id} checked={accusation.selectedSuspectId === suspect.id} onchange={() => setAccusationSelection(actions.setAccusationSuspect, suspect.id)} class="accent-[#963a31]" /><span class="text-sm font-semibold">{suspect.name}</span></label>{/each}</div></fieldset>
          <fieldset id="accusation-weapons"><legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">2 / Known weapon</legend><div class="mt-2 grid gap-2">{#each accusation.options?.weapons ?? [] as weapon}<label class={`flex min-h-11 cursor-pointer items-center gap-3 border px-3 py-2 ${accusation.selectedWeaponId === weapon.id ? "border-[#8c3f33] bg-[#f0dfbd]" : "border-[#9d8669] bg-[#e4d6b8]"}`}><input type="radio" name="accusation-weapon" value={weapon.id} checked={accusation.selectedWeaponId === weapon.id} onchange={() => setAccusationSelection(actions.setAccusationWeapon, weapon.id)} class="accent-[#963a31]" /><span class="text-sm font-semibold">{weapon.label}</span></label>{/each}</div></fieldset>
          <fieldset id="accusation-motives"><legend class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#725e48]">3 / Motive</legend><div class="mt-2 grid gap-2">{#each accusation.options?.motives ?? [] as motive}<label class={`flex min-h-11 cursor-pointer items-center gap-3 border px-3 py-2 ${accusation.selectedMotiveId === motive.id ? "border-[#8c3f33] bg-[#f0dfbd]" : "border-[#9d8669] bg-[#e4d6b8]"}`}><input type="radio" name="accusation-motive" value={motive.id} checked={accusation.selectedMotiveId === motive.id} onchange={() => setAccusationSelection(actions.setAccusationMotive, motive.id)} class="accent-[#963a31]" /><span class="text-sm font-semibold">{motive.label}</span></label>{/each}</div></fieldset>
        </div>

        {#if accusationConfirming}
          <div id="accusation-confirmation" class="mt-4 border-2 border-[#8c3f33] bg-[#eadbbc] p-4" role="alert">
            <p class="font-mono text-[9px] uppercase tracking-[0.12em] text-[#8c3f33]">Final seal check</p>
            <p class="mt-2 font-serif text-base font-semibold">
              {selectedAccusationSuspect?.name} / {selectedAccusationWeapon?.label} / {selectedAccusationMotive?.label}
            </p>
            <p class="mt-2 text-xs leading-5 text-[#695642]">
              {view.phase === "accusation"
                ? "This envelope cannot be changed after filing. Its contents stay private until every Detective submits."
                : "This spends your only Solve token. An incorrect accusation reveals only how many elements matched."}
            </p>
            <div class="mt-3 grid grid-cols-2 gap-2">
              <button id="casebook-cancel-accusation" type="button" onclick={() => (accusationConfirming = false)} class="min-h-11 cursor-pointer border border-[#796349] bg-[#d7c7aa] px-3 text-sm font-semibold">Revise deduction</button>
              <button id="casebook-confirm-accusation" type="button" onclick={confirmAccusation} class="min-h-11 cursor-pointer bg-[#8f372f] px-3 text-sm font-semibold text-[#fff0d6]">{view.phase === "accusation" ? "File sealed guess" : "Spend Solve token"}</button>
            </div>
          </div>
        {:else}
          <button id="casebook-submit-accusation" type="button" disabled={(!availableActions.has("accuse") && !availableActions.has("submit_final_guess")) || !selectedAccusationSuspect || !selectedAccusationWeapon || !selectedAccusationMotive} onclick={() => (accusationConfirming = true)} class="mt-4 min-h-12 w-full cursor-pointer bg-[#8f372f] px-4 text-sm font-semibold text-[#fff0d6] disabled:cursor-not-allowed disabled:opacity-40">{view.phase === "accusation" ? "Review final guess" : "Review Solve accusation"}</button>
        {/if}

        {#if view.phase !== "accusation"}<p class="mt-2 text-xs leading-5 text-[#695642]">A Solve accusation is legal only at the beginning of your turn, before any action is spent.</p>{/if}
      {/if}
    </section>
  {:else}
    <p id="accusation-unavailable" class="casebook-empty-page">No accusation sheet is authorized yet. The server opens this folio when a Solve attempt or final guess is legal.</p>
  {/if}

{:else if page === "history"}
  <section id="public-case-history" class="casebook-history-page" aria-labelledby="public-history-heading">
    <p class="font-mono text-[9px] uppercase tracking-[0.16em] text-[#8c3f33]">Public event ledger</p>
    <h3 id="public-history-heading" class="mt-1 font-serif text-xl font-semibold">Investigation history</h3>
    <p class="mt-2 border-l-2 border-[#8c3f33] pl-3 text-sm leading-6 text-[#4f3e30]" aria-live="polite">{history.lastEvent}</p>
    <ol id="public-history-list" class="mt-4 grid gap-2">
      {#each history.entries ?? [] as entry, index}<li id={`public-history-${index}`} class="casebook-history-entry"><span>{entry.type.replaceAll("_", " ")}</span><span>{entry.actorName}</span></li>{:else}<li class="casebook-empty-page">No public action has been filed yet.</li>{/each}
    </ol>
    {#if history.commandError && !history.commandStatus}
      <div id="game-command-error" class="mt-4 border-l-2 border-[#a54235] bg-[#e1cfad] p-3 text-xs leading-5" role="alert"><p>{history.commandError}</p>{#if history.retryAvailable}<button type="button" onclick={() => actions.retryCommand?.()} class="mt-2 cursor-pointer font-semibold text-[#8e352d] underline underline-offset-2">Retry command</button>{/if}</div>
    {/if}
  </section>

{:else if page === "chisel" && view.role === "chisel" && view.chisel}
  <section id="chisel-casebook-page" class="casebook-workspace-page bg-[#cab99a] p-4 sm:p-5" aria-labelledby="chisel-heading">
    <div class="flex items-center gap-3">
      <svg class="size-14 shrink-0 border border-[#533b2d] bg-[#231b17]" viewBox="0 0 64 64" role="img" aria-label="Original Chisel portrait token"><rect width="64" height="64" fill="#352720" /><path d="M12 25h40L44 12H21Z" fill="#111315" /><path d="M20 23c0 15 3 24 12 24s13-9 13-24Z" fill="#b18a68" /><path d="M18 64c2-14 7-20 14-20s14 6 16 20Z" fill="#7b3029" /><path d="M25 29h5m5 0h5" stroke="#1e1815" stroke-width="2" /></svg>
      <div class="min-w-0"><p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#7e3029]">Chisel · private case handler</p><h2 id="chisel-heading" class="break-words font-serif text-base font-semibold leading-tight">{view.chisel.identity?.display_name ?? "Unassigned"}</h2><p class="mt-1 font-mono text-[9px] uppercase text-[#715d47]">No turn · reacts to Detective actions</p></div>
    </div>
    <div class="mt-5 border-y border-[#9d8669] py-4">
      <p class="font-mono text-[9px] uppercase tracking-[0.14em] text-[#7e3029]">Private casebook</p>
      <p class="mt-2 font-serif text-sm italic leading-6 text-[#4e3d2f]">{view.chisel.casebook?.briefing ?? "No private briefing filed."}</p>
      <dl class="mt-4 space-y-2 text-xs"><div class="flex justify-between gap-3"><dt class="text-[#715d47]">Solution suspect</dt><dd class="font-mono font-semibold">{view.chisel.casebook?.solution?.suspect_id ?? "-"}</dd></div><div class="flex justify-between gap-3"><dt class="text-[#715d47]">Leverage held</dt><dd class="font-mono font-semibold">{Object.values(view.chisel.leverageByDetective ?? {}).reduce((sum, value) => sum + value, 0)}</dd></div><div class="flex justify-between gap-3"><dt class="text-[#715d47]">Pending response</dt><dd class="font-mono font-semibold">{view.chisel.pendingInterrogation ? "OPEN" : "NONE"}</dd></div></dl>
    </div>
  </section>
{/if}
