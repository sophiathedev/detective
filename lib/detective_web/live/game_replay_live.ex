defmodule DetectiveWeb.GameReplayLive do
  use DetectiveWeb, :live_view

  alias Detective.Games

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    case Games.replay_page(socket.assigns.current_scope, game_id, 0) do
      {:ok, replay} ->
        {:ok,
         socket
         |> assign_replay(replay)
         |> stream(:events, replay.events)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This sealed timeline is unavailable."))
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("replay_page", %{"page" => page}, socket) do
    with {page, ""} <- Integer.parse(page),
         true <- page >= 0,
         {:ok, replay} <-
           Games.replay_page(socket.assigns.current_scope, socket.assigns.game_id, page) do
      {:noreply,
       socket
       |> assign_replay(replay)
       |> stream(:events, replay.events, reset: true)}
    else
      _invalid -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="replay-shell"
        class="min-h-[calc(100dvh-3.5rem)] px-4 py-8 text-stone-100 sm:px-6 lg:px-10"
      >
        <div class="mx-auto max-w-[92rem]">
          <nav
            id="replay-navigation"
            class="mb-6 flex items-center justify-between gap-4"
            aria-label={gettext("Replay navigation")}
          >
            <.link
              id="replay-back-to-result"
              navigate={~p"/games/#{@game_id}"}
              class="inline-flex min-h-11 items-center gap-3 text-sm font-medium text-stone-300 transition hover:text-[var(--noir-gold-500)] focus-visible:outline-2 focus-visible:outline-offset-3 focus-visible:outline-[var(--noir-focus)]"
            >
              <span aria-hidden="true">←</span>
              {gettext("Return to case result")}
            </.link>
            <span class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--noir-gold-500)]">
              {gettext("Public evidence log")}
            </span>
          </nav>

          <section class="noir-wood-frame overflow-hidden p-3 sm:p-5" aria-labelledby="replay-title">
            <header class="noir-paper-sheet grid gap-6 p-6 sm:p-8 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
              <div>
                <p class="font-mono text-xs uppercase tracking-[0.2em] text-[var(--noir-red-700)]">
                  {gettext("Sealed chronology · Room %{code}", code: @room_code)}
                </p>
                <h1
                  id="replay-title"
                  class="mt-3 font-serif text-4xl font-semibold tracking-[-0.035em] text-[var(--noir-ink-900)] sm:text-5xl"
                >
                  {@title}
                </h1>
                <p class="mt-3 text-sm leading-6 text-[#66513c]">{@case_title}</p>
              </div>
              <div class="border-l-2 border-[var(--noir-red-700)] pl-4 text-right">
                <p class="font-mono text-[0.62rem] uppercase tracking-[0.12em] text-[#806b50]">
                  {gettext("Your disposition")}
                </p>
                <p class="mt-2 font-serif text-2xl font-semibold text-[var(--noir-ink-900)]">
                  {if @won, do: gettext("Case won"), else: gettext("Case lost")}
                </p>
                <p class="mt-1 font-mono text-[0.62rem] uppercase tracking-[0.1em] text-[#725f48]">
                  {gettext("Winner: %{role}", role: role_label(@winner_role))}
                </p>
              </div>
            </header>

            <section
              class="mt-3 border border-[var(--noir-gold-700)] bg-[var(--noir-ebony-900)] p-3 sm:p-5"
              aria-labelledby="replay-events-title"
            >
              <div class="flex items-end justify-between gap-4 border-b border-[var(--noir-gold-700)] pb-4">
                <div>
                  <p class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-[var(--noir-gold-500)]">
                    {gettext("Page %{page}", page: @page + 1)}
                  </p>
                  <h2 id="replay-events-title" class="mt-2 font-serif text-3xl font-semibold">
                    {gettext("Official field chronology")}
                  </h2>
                </div>
                <p class="max-w-md text-right text-xs leading-5 text-stone-400">
                  {gettext("Only public broadcasts are reproduced. Private notebooks remain sealed.")}
                </p>
              </div>

              <div id="replay-events" phx-update="stream" class="mt-4 grid gap-3">
                <p
                  id="replay-events-empty"
                  class="hidden only:block border border-dashed border-[var(--noir-gold-700)] p-6 text-center font-serif italic text-stone-500"
                >
                  {gettext("No public events were recorded on this page.")}
                </p>
                <article
                  :for={{dom_id, event} <- @streams.events}
                  id={dom_id}
                  class="noir-paper-sheet grid gap-4 p-5 sm:grid-cols-[5.5rem_minmax(0,1fr)_auto] sm:items-start"
                >
                  <div class="font-mono text-[0.62rem] uppercase tracking-[0.1em] text-[var(--noir-red-700)]">
                    <p>{gettext("Entry %{sequence}", sequence: event.sequence)}</p>
                    <time
                      class="mt-2 block text-[#806b50]"
                      datetime={DateTime.to_iso8601(event.inserted_at)}
                    >
                      {Calendar.strftime(event.inserted_at, "%H:%M:%S")}
                    </time>
                  </div>
                  <div>
                    <h3 class="font-serif text-xl font-semibold text-[var(--noir-ink-900)]">
                      {event_title(event.event_type)}
                    </h3>
                    <p class="mt-2 text-sm leading-6 text-[#66513c]">
                      {event_detail(event, @players, @reference)}
                    </p>
                  </div>
                  <span class="justify-self-start border border-[#8f7658] px-2 py-1 font-mono text-[0.55rem] uppercase tracking-[0.1em] text-[#725f48] sm:justify-self-end">
                    {event.event_type |> String.replace("_", " ")}
                  </span>
                </article>
              </div>

              <nav
                class="mt-5 flex items-center justify-between gap-3 border-t border-[var(--noir-gold-700)] pt-4"
                aria-label={gettext("Replay pages")}
              >
                <button
                  id="replay-previous-page"
                  type="button"
                  phx-click="replay_page"
                  phx-value-page={@page - 1}
                  disabled={!@has_previous}
                  class="noir-physical-button px-4 text-sm font-semibold disabled:cursor-not-allowed disabled:opacity-35"
                >
                  {gettext("Previous entries")}
                </button>
                <span class="font-mono text-[0.62rem] uppercase tracking-[0.12em] text-stone-400">
                  {gettext("Chronology page %{page}", page: @page + 1)}
                </span>
                <button
                  id="replay-next-page"
                  type="button"
                  phx-click="replay_page"
                  phx-value-page={@page + 1}
                  disabled={!@has_next}
                  class="noir-physical-button px-4 text-sm font-semibold disabled:cursor-not-allowed disabled:opacity-35"
                >
                  {gettext("Next entries")}
                </button>
              </nav>
            </section>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_replay(socket, replay) do
    assign(socket,
      page_title: gettext("Case replay"),
      game_id: replay.id,
      title: replay.title,
      case_title: replay.case_title,
      room_code: replay.room_code,
      won: replay.won,
      winner_role: replay.winner_role,
      players: replay.players,
      reference: replay.reference,
      page: replay.page,
      has_previous: replay.has_previous,
      has_next: replay.has_next
    )
  end

  defp event_title("game_started"), do: gettext("Investigation opened")
  defp event_title("detective_placed"), do: gettext("Detective deployed")
  defp event_title("player_moved"), do: gettext("Movement logged")
  defp event_title("location_searched"), do: gettext("Location searched")
  defp event_title("suspect_searched"), do: gettext("Subject searched")
  defp event_title("interrogation_started"), do: gettext("Interrogation opened")
  defp event_title("response_published"), do: gettext("Statement entered")
  defp event_title("challenge_succeeded"), do: gettext("Statement broken")
  defp event_title("challenge_failed"), do: gettext("Challenge rejected")
  defp event_title("accusation_submitted"), do: gettext("Accusation filed")
  defp event_title("accusation_rejected"), do: gettext("Accusation rejected")
  defp event_title("final_guess_submitted"), do: gettext("Final deduction sealed")
  defp event_title("game_finished"), do: gettext("Case closed")
  defp event_title("game_paused"), do: gettext("Field work suspended")
  defp event_title("game_resumed"), do: gettext("Field work resumed")
  defp event_title("turn_started"), do: gettext("New field turn")
  defp event_title("turn_ended"), do: gettext("Field turn closed")
  defp event_title("day_advanced"), do: gettext("A new day began")

  defp event_title(type) do
    type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp event_detail(event, players, reference) do
    payload = event.public_payload || %{}
    actor = player_name(players, payload)

    case event.event_type do
      "game_started" ->
        gettext("The case file was opened and the first field turn was assigned.")

      "detective_placed" ->
        gettext("%{actor} reported to %{location}.",
          actor: actor,
          location: location_name(reference, payload["location_id"])
        )

      "player_moved" ->
        gettext("%{actor} moved from %{from} to %{destination}.",
          actor: actor,
          from: location_name(reference, payload["from_location_id"]),
          destination: location_name(reference, payload["location_id"])
        )

      type when type in ["location_searched", "suspect_searched"] ->
        gettext("%{actor} searched %{target} and filed the public result.",
          actor: actor,
          target: replay_target(reference, payload)
        )

      "interrogation_started" ->
        gettext("%{actor} questioned %{suspect} about lead %{topic}.",
          actor: actor,
          suspect: suspect_name(reference, payload["suspect_id"]),
          topic: payload["topic_code"] || "—"
        )

      "challenge_succeeded" ->
        gettext("%{actor} exposed a false statement.", actor: actor)

      "challenge_failed" ->
        gettext("%{actor} challenged a statement that held up.", actor: actor)

      "accusation_submitted" ->
        gettext("%{actor} committed to a formal accusation.", actor: actor)

      "game_finished" ->
        gettext("The server sealed the solution and declared the winning side.")

      _other ->
        gettext("A public action was entered into the official chronology.")
    end
  end

  defp player_name(players, payload) do
    player_id =
      payload["player_id"] || payload["detective_player_id"] || payload["chisel_player_id"]

    Map.get(players, player_id, gettext("The field team"))
  end

  defp replay_target(reference, %{"target_type" => "suspect", "target_id" => id}),
    do: suspect_name(reference, id)

  defp replay_target(reference, payload),
    do: location_name(reference, payload["target_id"] || payload["location_id"])

  defp location_name(reference, id),
    do: Map.get(reference.locations, id, id || gettext("an undisclosed location"))

  defp suspect_name(reference, id),
    do: Map.get(reference.suspects, id, id || gettext("an unnamed subject"))

  defp role_label("detective"), do: gettext("Detectives")
  defp role_label("chisel"), do: gettext("Chisel")
  defp role_label(_role), do: gettext("Undetermined")
end
