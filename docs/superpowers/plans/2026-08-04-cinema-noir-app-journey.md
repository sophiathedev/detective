# Cinema Noir App Journey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved charred-ebony, antique-gold, sepia-paper, and signal-red board-game language to the public shell, account screens, Dashboard, Create Game, Invite, and Lobby.

**Architecture:** Keep Phoenix LiveView responsible for authentication, forms, queries, and navigation while LiveSvelte renders product screens. Add shared Svelte visual primitives plus shared CSS material classes; screens consume narrow allow-listed props and preserve all existing DOM IDs and events. Add one Dashboard projection for case-file rows without changing game membership authority.

**Tech Stack:** Elixir, Phoenix 1.8, LiveView, LiveSvelte, Svelte 5, Tailwind CSS 4, Vitest, Testing Library, ExUnit, PostgreSQL.

## Global Constraints

- Keep Tailwind v4 imports using `@import "tailwindcss" source(none)` and the existing `@source` declarations.
- Do not use DaisyUI, `@apply`, external script tags, or external stylesheet tags.
- Runtime graphics must be local SVG, WebP, or AVIF assets with solid-color fallbacks.
- Keep IBM Plex Serif, Sans, and Mono as the complete font system.
- Keep Dashboard, Create Game, Invite, Lobby, and Game routes in the existing `live_session :require_authenticated_user` and `:require_authenticated_user` browser pipeline.
- Keep public account and Home routes in the existing `live_session :current_user`; never duplicate a `live_session` name.
- Every LiveView template begins with `<Layouts.app flash={@flash} current_scope={@current_scope}>`.
- Templates access the authenticated user through `@current_scope.user`, never `@current_user`.
- Keep `<.flash_group>` inside `DetectiveWeb.Layouts` only.
- Keep generated `<.input>` and `to_form/2` on HEEx account forms.
- Preserve unrelated `.agents/`, `.superpowers/`, `output/`, and `skills-lock.json` files.
- Prefix every shell command with `rtk`.

---

## File Map

### Shared presentation

- Create `assets/svelte/ui/WoodFrame.svelte`: semantic wood-frame wrapper.
- Create `assets/svelte/ui/PaperSheet.svelte`: semantic sepia-paper wrapper.
- Create `assets/svelte/ui/StatusStamp.svelte`: non-interactive visible status treatment.
- Create `assets/svelte/ui/PortraitToken.svelte`: shared original silhouette token.
- Create `assets/svelte/ui/NoirPrimitives.test.js`: semantic and accessibility contract.
- Create `priv/static/images/ui/noir/wood-grain.svg`: low-contrast local wood pattern.
- Create `priv/static/images/ui/noir/paper-fiber.svg`: low-contrast local paper pattern.
- Create `priv/static/images/ui/noir/portraits/detective-1.webp`: original blue-coat Detective portrait.
- Create `priv/static/images/ui/noir/portraits/detective-2.webp`: original oxblood-coat Detective portrait.
- Create `priv/static/images/ui/noir/portraits/detective-3.webp`: original green-coat Detective portrait.
- Create `priv/static/images/ui/noir/portraits/detective-4.webp`: original ochre-coat Detective portrait.
- Create `priv/static/images/ui/noir/portraits/chisel.webp`: original Chisel portrait.
- Create `priv/static/images/ui/noir/portraits/source.json`: generation prompt and asset provenance.
- Modify `assets/css/app.css`: material tokens, primitives, controls, focus, motion, and responsive rules.

### Phoenix shell and accounts

- Modify `lib/detective_web/components/layouts/root.html.heex`: ebony account rail.
- Modify `lib/detective_web/components/layouts.ex`: shared app-shell class.
- Modify `lib/detective_web/components/core_components.ex`: paper/status flash treatment.
- Modify `lib/detective_web/live/home_live.ex`: remove scaffold counter props and events.
- Modify `assets/svelte/Home.svelte`: public noir case-desk landing screen.
- Create `assets/svelte/Home.test.js`: public CTA and semantic landmark coverage.
- Modify `lib/detective_web/live/user_live/login.ex`: paper login dossier.
- Modify `lib/detective_web/live/user_live/registration.ex`: paper registration dossier.
- Modify `lib/detective_web/live/user_live/confirmation.ex`: sealed confirmation dossier.
- Modify `lib/detective_web/live/user_live/settings.ex`: tabbed account dossier.
- Modify existing Home and account LiveView tests to assert stable IDs.

### Product journey

- Modify `lib/detective/games.ex`: add allow-listed case-file Dashboard projection.
- Modify `test/detective/games_test.exs`: projection grouping and membership tests.
- Modify `lib/detective_web/live/dashboard_live.ex`: pass case-file rows.
- Modify `test/detective_web/live/dashboard_live_test.exs`: allow-list prop test.
- Modify `assets/svelte/Dashboard.svelte`: case cabinet UI.
- Create `assets/svelte/Dashboard.test.js`: drawer grouping and empty-state tests.
- Modify `assets/svelte/CreateGame.svelte`: case-opening document UI.
- Create `assets/svelte/CreateGame.test.js`: form semantics and created-room tests.
- Modify `assets/svelte/Invite.svelte`: sealed summons UI.
- Create `assets/svelte/Invite.test.js`: valid and unavailable invitation states.
- Modify `assets/svelte/Lobby.svelte`: player tray UI without changing Channel logic.
- Create `assets/svelte/Lobby.test.js`: Chisel, four seats, and Presence semantics.

---

### Task 1: Add shared noir materials and primitives

**Files:**
- Create: `assets/svelte/ui/WoodFrame.svelte`
- Create: `assets/svelte/ui/PaperSheet.svelte`
- Create: `assets/svelte/ui/StatusStamp.svelte`
- Create: `assets/svelte/ui/PortraitToken.svelte`
- Create: `assets/svelte/ui/NoirPrimitives.test.js`
- Create: `priv/static/images/ui/noir/wood-grain.svg`
- Create: `priv/static/images/ui/noir/paper-fiber.svg`
- Create: `priv/static/images/ui/noir/portraits/detective-1.webp`
- Create: `priv/static/images/ui/noir/portraits/detective-2.webp`
- Create: `priv/static/images/ui/noir/portraits/detective-3.webp`
- Create: `priv/static/images/ui/noir/portraits/detective-4.webp`
- Create: `priv/static/images/ui/noir/portraits/chisel.webp`
- Create: `priv/static/images/ui/noir/portraits/source.json`
- Modify: `assets/css/app.css:1-30`

**Interfaces:**
- Produces: `WoodFrame({as, id, class, labelledby, children})`.
- Produces: `PaperSheet({as, id, class, labelledby, tilt, children})`.
- Produces: `StatusStamp({tone, children})`, where `tone` is `neutral`, `ready`, `danger`, or `sealed`.
- Produces: `PortraitToken({name, role, seat, size})`, with `size` equal to `sm`, `md`, or `lg`.
- Produces: CSS classes `noir-wood-frame`, `noir-paper-sheet`, `noir-status-stamp`, `noir-physical-button`, and `noir-field`.

- [ ] **Step 1: Write failing primitive tests**

```javascript
import { createRawSnippet } from "svelte"
import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import PaperSheet from "./PaperSheet.svelte"
import PortraitToken from "./PortraitToken.svelte"
import StatusStamp from "./StatusStamp.svelte"
import WoodFrame from "./WoodFrame.svelte"

const snippet = (text) => createRawSnippet(() => ({ render: () => text }))

describe("noir visual primitives", () => {
  it("preserves requested semantic elements and labels", () => {
    render(WoodFrame, {
      as: "section",
      id: "case-frame",
      labelledby: "case-title",
      children: snippet("Case"),
    })
    render(PaperSheet, {
      as: "article",
      id: "case-paper",
      labelledby: "case-title",
      children: snippet("Paper"),
    })

    expect(document.querySelector("section#case-frame.noir-wood-frame")).toHaveAttribute(
      "aria-labelledby",
      "case-title",
    )
    expect(document.querySelector("article#case-paper.noir-paper-sheet")).toHaveAttribute(
      "aria-labelledby",
      "case-title",
    )
  })

  it("prints status text and an accessible textured portrait", () => {
    render(StatusStamp, { tone: "ready", children: snippet("Ready") })
    render(PortraitToken, { name: "Mara Voss", role: "detective", seat: 2, size: "md" })

    expect(screen.getByText("Ready")).toHaveClass("noir-status-stamp-ready")
    expect(screen.getByRole("img", { name: "Detective portrait for Mara Voss" })).toHaveAttribute(
      "src",
      "/images/ui/noir/portraits/detective-2.webp",
    )
  })
})
```

- [ ] **Step 2: Run the test and verify missing modules fail**

Run: `rtk npm run test:ui -- assets/svelte/ui/NoirPrimitives.test.js`

Expected: FAIL because the four Svelte modules do not exist.

- [ ] **Step 3: Implement semantic wrappers**

`WoodFrame.svelte`:

```svelte
<script>
  let {
    as = "section",
    id = undefined,
    class: className = "",
    labelledby = undefined,
    children,
  } = $props()
</script>

<svelte:element
  this={as}
  {id}
  aria-labelledby={labelledby}
  class={`noir-wood-frame ${className}`}
>
  {@render children?.()}
</svelte:element>
```

`PaperSheet.svelte`:

```svelte
<script>
  let {
    as = "article",
    id = undefined,
    class: className = "",
    labelledby = undefined,
    tilt = "none",
    children,
  } = $props()
</script>

<svelte:element
  this={as}
  {id}
  aria-labelledby={labelledby}
  data-tilt={tilt}
  class={`noir-paper-sheet ${className}`}
>
  {@render children?.()}
</svelte:element>
```

`StatusStamp.svelte`:

```svelte
<script>
  let { tone = "neutral", children } = $props()
</script>

<span class={`noir-status-stamp noir-status-stamp-${tone}`}>
  {@render children?.()}
</span>
```

`PortraitToken.svelte` uses the generated local portrait set:

```svelte
<script>
  let { name, role = "detective", seat = 1, size = "md" } = $props()
  let label = $derived(`${role === "chisel" ? "Chisel" : "Detective"} portrait for ${name}`)
  let src = $derived(
    role === "chisel"
      ? "/images/ui/noir/portraits/chisel.webp"
      : `/images/ui/noir/portraits/detective-${Math.min(Math.max(seat, 1), 4)}.webp`,
  )
</script>

<img class={`noir-portrait noir-portrait-${size}`} {src} alt={label} draggable="false" />
```

- [ ] **Step 4: Add local textures and material CSS**

Use these CSS variables and classes at the top of `app.css`, after `@theme`:

```css
:root {
  --noir-ebony-950: #090807;
  --noir-ebony-900: #0f0d0c;
  --noir-ebony-800: #1c1815;
  --noir-ebony-700: #2b251f;
  --noir-gold-500: #c2a35f;
  --noir-gold-700: #746039;
  --noir-paper-100: #eadbbd;
  --noir-paper-300: #ccb68d;
  --noir-paper-500: #a98d63;
  --noir-ink-900: #251c16;
  --noir-red-500: #aa392f;
  --noir-red-700: #641d18;
  --noir-focus: #f2d890;
}

.noir-wood-frame {
  position: relative;
  border: 1px solid var(--noir-gold-700);
  border-radius: 1rem;
  background-color: var(--noir-ebony-800);
  background-image: url("/images/ui/noir/wood-grain.svg");
  box-shadow: 0 1.5rem 3.5rem rgb(0 0 0 / 0.42), inset 0 0 0 3px var(--noir-ebony-950);
}

.noir-paper-sheet {
  position: relative;
  color: var(--noir-ink-900);
  background-color: var(--noir-paper-300);
  background-image: url("/images/ui/noir/paper-fiber.svg");
  box-shadow: 0 1rem 2.25rem rgb(0 0 0 / 0.34), inset 0 0 2rem rgb(92 58 34 / 0.12);
}

.noir-paper-sheet[data-tilt="left"] { rotate: -0.35deg; }
.noir-paper-sheet[data-tilt="right"] { rotate: 0.35deg; }

.noir-status-stamp {
  display: inline-flex;
  border: 2px solid currentColor;
  padding: 0.3rem 0.5rem;
  font-family: "IBM Plex Mono", ui-monospace, monospace;
  font-size: 0.625rem;
  font-weight: 600;
  letter-spacing: 0.12em;
  line-height: 1;
  text-transform: uppercase;
}

.noir-status-stamp-ready { color: #355844; }
.noir-status-stamp-danger { color: var(--noir-red-700); }
.noir-status-stamp-sealed { color: var(--noir-red-500); rotate: -2deg; }
.noir-status-stamp-neutral { color: #68563f; }

.noir-physical-button {
  min-height: 2.75rem;
  cursor: pointer;
  border: 1px solid var(--noir-gold-700);
  border-radius: 0.45rem;
  background: linear-gradient(#332b24, #15120f);
  box-shadow: 0 0.25rem 0 var(--noir-ebony-950), inset 0 0 0 1px rgb(194 163 95 / 0.2);
  color: #f2e2c3;
  transition: border-color 140ms ease, transform 140ms ease, box-shadow 140ms ease;
}

.noir-physical-button:hover:not(:disabled) { border-color: var(--noir-gold-500); transform: translateY(-1px); }
.noir-physical-button:active:not(:disabled) { box-shadow: 0 0.1rem 0 var(--noir-ebony-950); transform: translateY(2px); }
.noir-physical-button:focus-visible { outline: 3px solid var(--noir-focus); outline-offset: 3px; }
.noir-physical-button:disabled { cursor: not-allowed; opacity: 0.45; }
```

Create `wood-grain.svg` as a 160 by 80 subtle pattern and `paper-fiber.svg` as a 120 by 120 subtle pattern. Both SVGs must contain only local vector paths, use opacity below `0.12`, and include no script or external reference.

Invoke the `imagegen` skill to create five separate square portraits with this
art direction: original 1940s Los Angeles noir board-game characters,
painterly gouache plus engraved paper texture, waist-up, hard side lighting,
muted cinema-noir palette, clean dark background, consistent camera and crop,
no text, no logo, no copied board-game illustration. Export at 512 by 512 as
the exact WebP filenames listed above. Record the prompt, generation date, and
statement `Original generated interface art; not copied from commercial card
artwork` in `source.json`.

- [ ] **Step 5: Run primitive tests and asset build**

Run: `rtk npm run test:ui -- assets/svelte/ui/NoirPrimitives.test.js`

Expected: PASS.

Run: `rtk mix assets.build`

Expected: Vite client and SSR builds complete without warnings.

- [ ] **Step 6: Commit**

```bash
rtk git add assets/css/app.css assets/svelte/ui priv/static/images/ui/noir
rtk git commit -m "feat(ui): add noir material system"
```

### Task 2: Restyle the Phoenix shell and flash system

**Files:**
- Modify: `lib/detective_web/components/layouts/root.html.heex:1-48`
- Modify: `lib/detective_web/components/layouts.ex:25-76`
- Modify: `lib/detective_web/components/core_components.ex:43-80`
- Modify: `test/detective_web/live/home_live_test.exs`

**Interfaces:**
- Consumes: material CSS from Task 1.
- Produces: `#app-shell.noir-app-shell`, `#account-navigation.noir-wood-nav`, and `.noir-flash-paper`.

- [ ] **Step 1: Add failing shell assertions**

Add to the first Home test:

```elixir
assert has_element?(view, "#app-shell.noir-app-shell")
assert has_element?(view, "#home-frontend")
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `rtk mix test test/detective_web/live/home_live_test.exs:7`

Expected: FAIL because `#app-shell` lacks `noir-app-shell`.

- [ ] **Step 3: Apply shell classes without changing route or auth logic**

Change the app layout root to:

```heex
<main id="app-shell" class="noir-app-shell">
  {render_slot(@inner_block)}
</main>

<.flash_group flash={@flash} />
```

Set the root body to:

```heex
<body class="min-h-screen bg-[var(--noir-ebony-950)] font-sans text-stone-100 antialiased">
```

Add `noir-wood-nav` to `#account-navigation`, preserve every existing link and
conditional branch, and replace rounded dashboard-like hover fills with gold
text and a visible focus outline.

Change the inner flash surface class to include `noir-flash-paper` and replace
blue/red utility backgrounds with paper, ink, and status-red classes. Keep the
outer `role="alert"`, close button, icons, IDs, and JS commands unchanged.

- [ ] **Step 4: Add shell CSS**

```css
.noir-app-shell {
  min-height: calc(100dvh - 3.5rem);
  background:
    radial-gradient(circle at 50% -20%, rgb(61 51 42 / 0.45), transparent 40%),
    var(--noir-ebony-950);
}

.noir-wood-nav {
  background-color: var(--noir-ebony-800);
  background-image: url("/images/ui/noir/wood-grain.svg");
  box-shadow: inset 0 -1px var(--noir-gold-700), 0 0.5rem 1.5rem rgb(0 0 0 / 0.28);
}

.noir-flash-paper {
  border: 1px solid var(--noir-gold-700);
  border-radius: 0.35rem;
  background: var(--noir-paper-100) url("/images/ui/noir/paper-fiber.svg");
  color: var(--noir-ink-900);
  box-shadow: 0 1rem 2.5rem rgb(0 0 0 / 0.45);
}
```

- [ ] **Step 5: Verify shell tests**

Run: `rtk mix test test/detective_web/live/home_live_test.exs`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add assets/css/app.css lib/detective_web/components test/detective_web/live/home_live_test.exs
rtk git commit -m "feat(ui): frame Phoenix shell in ebony"
```

### Task 3: Redesign Home and account dossiers

**Files:**
- Modify: `lib/detective_web/live/home_live.ex`
- Modify: `assets/svelte/Home.svelte`
- Create: `assets/svelte/Home.test.js`
- Modify: `lib/detective_web/live/user_live/login.ex`
- Modify: `lib/detective_web/live/user_live/registration.ex`
- Modify: `lib/detective_web/live/user_live/confirmation.ex`
- Modify: `lib/detective_web/live/user_live/settings.ex`
- Modify: `test/detective_web/live/home_live_test.exs`
- Modify: `test/detective_web/live/user_live/login_test.exs`
- Modify: `test/detective_web/live/user_live/registration_test.exs`
- Modify: `test/detective_web/live/user_live/settings_test.exs`

**Interfaces:**
- Consumes: shared material CSS and primitives from Tasks 1-2.
- Produces: Home props `%{signed_in: boolean}` and stable IDs `#home-case-desk`, `#auth-login-sheet`, `#auth-registration-sheet`, and `#account-settings-dossier`.

- [ ] **Step 1: Write failing Home and account structure tests**

`Home.test.js`:

```javascript
import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import Home from "./Home.svelte"

describe("Home", () => {
  it("offers account entry from the public case desk", () => {
    render(Home, { signed_in: false })
    expect(document.querySelector("#home-case-desk.noir-wood-frame")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Open an account" })).toHaveAttribute("href", "/users/register")
    expect(screen.getByRole("link", { name: "Log in" })).toHaveAttribute("href", "/users/log-in")
  })

  it("sends an authenticated user to the case cabinet", () => {
    render(Home, { signed_in: true })
    expect(screen.getByRole("link", { name: "Open case cabinet" })).toHaveAttribute("href", "/dashboard")
  })
})
```

Replace HomeLive's scaffold counter assertions with:

```elixir
import Detective.AccountsFixtures

test "renders the public LiveSvelte case desk", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/")
  component = get_svelte(view, id: "home-frontend")
  assert component.name == "Home"
  refute component.props["signed_in"]
end

test "projects signed-in state without user details", %{conn: conn} do
  user = user_fixture()
  {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/")
  component = get_svelte(view, id: "home-frontend")
  assert component.props["signed_in"]
  refute Map.has_key?(component.props, "email")
end
```

Add these LiveView assertions:

```elixir
assert has_element?(lv, "#auth-login-sheet.noir-paper-sheet")
assert has_element?(lv, "#login_form_magic")
assert has_element?(lv, "#login_form_password")
```

```elixir
assert has_element?(lv, "#auth-registration-sheet.noir-paper-sheet")
assert has_element?(lv, "#registration_form")
```

```elixir
assert has_element?(lv, "#account-settings-dossier.noir-paper-sheet")
assert has_element?(lv, "#profile_form")
assert has_element?(lv, "#email_form")
assert has_element?(lv, "#password_form")
```

- [ ] **Step 2: Run focused tests and verify failure**

Run: `rtk npm run test:ui -- assets/svelte/Home.test.js`

Expected: FAIL because Home still expects scaffold props and lacks the case desk.

Run: `rtk mix test test/detective_web/live/user_live/login_test.exs test/detective_web/live/user_live/registration_test.exs test/detective_web/live/user_live/settings_test.exs`

Expected: FAIL on the new noir wrapper selectors.

- [ ] **Step 3: Replace Home scaffold state with a signed-in projection**

Use this mount contract:

```elixir
def mount(_params, _session, socket) do
  {:ok,
   assign(socket,
     page_title: "Detective: City of Angels",
     signed_in: not is_nil(socket.assigns.current_scope)
   )}
end
```

Delete the counter handlers. Render LiveSvelte with only:

```elixir
props={%{signed_in: @signed_in}}
```

`Home.svelte` must use `WoodFrame`, `PaperSheet`, and `StatusStamp`; render a
public case-desk hero, concise game premise, authentication CTA, and the
non-commercial fan-project notice. Do not retain framework version cards or
external framework documentation links.

- [ ] **Step 4: Wrap account forms in semantic paper dossiers**

Replace Login's current outer `div` with the following `section` and paper
wrapper. Move the existing local-mail notice, both forms, divider, and account
navigation inside the wrapper after the heading. Apply matching IDs to
Registration, Confirmation, and Settings:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <section class="noir-auth-desk px-4 py-12 sm:px-6 sm:py-20" aria-labelledby="login-title">
    <div id="auth-login-sheet" class="noir-paper-sheet mx-auto max-w-lg p-6 sm:p-10">
      <p class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--noir-red-700)]">
        Identity file
      </p>
      <h1 id="login-title" class="mt-3 font-serif text-4xl font-semibold text-[var(--noir-ink-900)]">
        Log in
      </h1>
    </div>
  </section>
</Layouts.app>
```

Keep every existing `<.form>`, `<.input>`, hidden field, action, validation,
sudo-mode branch, and navigation target. Add only wrappers, IDs, noir classes,
and concise detective-file copy. Add `.noir-auth-desk` and scoped form-control
styles to `app.css`; do not override `<.input class>` values.

- [ ] **Step 5: Run account and Home tests**

Run: `rtk npm run test:ui -- assets/svelte/Home.test.js`

Expected: PASS.

Run: `rtk mix test test/detective_web/live/home_live_test.exs test/detective_web/live/user_live`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add assets/css/app.css assets/svelte/Home.svelte assets/svelte/Home.test.js lib/detective_web/live/home_live.ex lib/detective_web/live/user_live test/detective_web/live/home_live_test.exs test/detective_web/live/user_live
rtk git commit -m "feat(ui): redesign public and account desks"
```

### Task 4: Add Dashboard case-file projections and cabinet UI

**Files:**
- Modify: `lib/detective/games.ex:122-138`
- Modify: `test/detective/games_test.exs`
- Modify: `lib/detective_web/live/dashboard_live.ex`
- Modify: `test/detective_web/live/dashboard_live_test.exs`
- Modify: `assets/svelte/Dashboard.svelte`
- Create: `assets/svelte/Dashboard.test.js`

**Interfaces:**
- Produces: `Games.list_game_dossiers/1` returning `%{waiting: [], active: [], finished: []}`.
- Context rows contain only `id`, `title`, `room_code`, `status`, `phase`, `role`, `case_title`, `detective_count`, `max_detectives`, and `updated_at`.
- `DashboardLive` adds the verified `path` field before serialization.
- Dashboard Svelte consumes `display_name`, `games`, and `dossiers`.

- [ ] **Step 1: Write failing context projection test**

```elixir
test "lists only active memberships as allow-listed dashboard dossiers" do
  user = user_fixture()
  outsider = user_fixture()
  %{game: own_game} = game_fixture(user, %{title: "Own File", max_detectives: 3})
  %{game: other_game} = game_fixture(outsider, %{title: "Secret File"})

  dossiers = Games.list_game_dossiers(Scope.for_user(user))

  assert [%{id: id, title: "Own File", role: "chisel", max_detectives: 3}] = dossiers.waiting
  assert id == own_game.id
  refute Enum.any?(dossiers.waiting, &(&1.id == other_game.id))
  refute Map.has_key?(hd(dossiers.waiting), :case_content)
end
```

- [ ] **Step 2: Run the test and verify undefined function failure**

Run: `rtk mix test test/detective/games_test.exs`

Expected: FAIL because `list_game_dossiers/1` is undefined.

- [ ] **Step 3: Implement the query and bucket function**

```elixir
def list_game_dossiers(%Scope{user: user}) do
  detective_counts =
    GamePlayer
    |> where([player], player.status == "active" and player.role == "detective")
    |> group_by([player], player.game_id)
    |> select([player], %{game_id: player.game_id, count: count(player.id)})

  rows =
    GamePlayer
    |> join(:inner, [player], game in assoc(player, :game))
    |> join(:inner, [_player, game], version in assoc(game, :case_version))
    |> join(:inner, [_player, _game, version], case_file in assoc(version, :case_file))
    |> join(:left, [_player, game], counts in subquery(detective_counts),
      on: counts.game_id == game.id
    )
    |> where(
      [player, game],
      player.user_id == ^user.id and player.status == "active" and
        game.status in ["waiting", "active", "paused", "finished"]
    )
    |> order_by([_player, game], desc: game.updated_at)
    |> select([player, game, _version, case_file, counts], %{
      id: game.id,
      title: game.title,
      room_code: game.room_code,
      status: game.status,
      phase: game.phase,
      role: player.role,
      case_title: case_file.title,
      detective_count: fragment("COALESCE(?, 0)", counts.count),
      max_detectives: game.max_detectives,
      updated_at: game.updated_at
    })
    |> Repo.all()

  Enum.reduce(rows, %{waiting: [], active: [], finished: []}, fn row, acc ->
    bucket = dashboard_bucket(row.status)
    Map.update!(acc, bucket, &(&1 ++ [row]))
  end)
end

defp dashboard_bucket("waiting"), do: :waiting
defp dashboard_bucket(status) when status in ["active", "paused"], do: :active
defp dashboard_bucket("finished"), do: :finished
```

- [ ] **Step 4: Pass and test the allow-listed LiveSvelte prop**

Assign the context result in `DashboardLive.mount/3`, add verified paths in the
web layer, and pass it as `dossiers`:

```elixir
game_dossiers =
  socket.assigns.current_scope
  |> Games.list_game_dossiers()
  |> Map.new(fn {bucket, rows} ->
    {bucket,
     Enum.map(rows, fn row ->
       path =
         if row.status == "waiting",
           do: ~p"/games/#{row.id}/lobby",
           else: ~p"/games/#{row.id}"

       Map.put(row, :path, path)
     end)}
  end)
```

Add:

```elixir
assert %{"waiting" => waiting, "active" => [], "finished" => []} =
         component.props["dossiers"]

assert [%{"role" => "chisel"} = dossier] = waiting
refute Map.has_key?(dossier, "case_content")
refute Map.has_key?(dossier, "solution")
```

- [ ] **Step 5: Write the failing Svelte cabinet test**

```javascript
import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import Dashboard from "./Dashboard.svelte"

const waiting = {
  id: "g1",
  title: "Midnight Bureau",
  room_code: "ABC234",
  status: "waiting",
  phase: "lobby",
  role: "chisel",
  case_title: "The Pendleton Murders",
  detective_count: 1,
  max_detectives: 4,
  path: "/games/g1/lobby",
}

describe("Dashboard", () => {
  it("renders case drawers by server bucket", () => {
    render(Dashboard, {
      display_name: "Mara",
      games: { waiting: 1, active: 0, finished: 0 },
      dossiers: { waiting: [waiting], active: [], finished: [] },
    })

    expect(document.querySelector("#dashboard-case-cabinet.noir-wood-frame")).toBeInTheDocument()
    expect(screen.getByRole("link", { name: /Open Midnight Bureau/i })).toHaveAttribute(
      "href",
      "/games/g1/lobby",
    )
    expect(screen.queryByText("No investigations yet")).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 6: Implement the case cabinet**

Replace the abstract city-card layout with:

- `WoodFrame` as `#dashboard-case-cabinet`.
- Three semantic sections headed Waiting, Active, and Closed.
- One paper/file drawer link for each server row, with accessible name
  `Open ${game.title}`.
- Role, room code, case title, phase, and seat count printed on each drawer.
- `#dashboard-empty-state` only when all three arrays are empty.
- Existing `#dashboard-new-game`, summary IDs, and `/games/new` paths preserved.

- [ ] **Step 7: Run Dashboard tests**

Run: `rtk mix test test/detective/games_test.exs test/detective_web/live/dashboard_live_test.exs`

Expected: PASS.

Run: `rtk npm run test:ui -- assets/svelte/Dashboard.test.js`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
rtk git add lib/detective/games.ex lib/detective_web/live/dashboard_live.ex test/detective/games_test.exs test/detective_web/live/dashboard_live_test.exs assets/svelte/Dashboard.svelte assets/svelte/Dashboard.test.js
rtk git commit -m "feat(dashboard): add case-file cabinet"
```

### Task 5: Turn Create Game into a case-opening document

**Files:**
- Modify: `assets/svelte/CreateGame.svelte`
- Create: `assets/svelte/CreateGame.test.js`
- Modify: `lib/detective/games/game.ex`
- Modify: `test/detective/games_test.exs`
- Modify: `test/detective/invitations_test.exs`
- Modify: `test/detective_web/live/game_new_live_test.exs`

**Interfaces:**
- Consumes: existing `form`, `case_options`, `global_error`, and `created_room` props unchanged.
- Preserves: `phx-change="validate"`, `phx-submit="save"`, every `game[...]` field name, and created-room IDs.
- Enforces: Classic room capacity is two to four Detectives; one-Detective head-to-head is outside the current ruleset.

- [ ] **Step 1: Write failing Svelte tests**

```javascript
import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import CreateGame from "./CreateGame.svelte"

const baseProps = {
  form: {
    fields: { title: "", case_version_id: "", max_detectives: "4", invite_hours: "24" },
    errors: {},
  },
  case_options: [{ value: "v1", label: "Pendleton v1", description: "Public synopsis" }],
  global_error: null,
  created_room: null,
}

describe("CreateGame", () => {
  it("renders a semantic case-opening form", () => {
    render(CreateGame, baseProps)
    expect(document.querySelector("#create-game-document.noir-paper-sheet")).toBeInTheDocument()
    expect(screen.getByRole("textbox", { name: "Room name" })).toHaveAttribute("name", "game[title]")
    expect(screen.getByRole("radio", { name: /Pendleton v1/i })).toHaveAttribute(
      "name",
      "game[case_version_id]",
    )
    expect(screen.queryByRole("option", { name: "1 detective" })).not.toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Seal and create room" })).toBeEnabled()
  })

  it("renders the raw invitation only in the created-room sheet", () => {
    render(CreateGame, {
      ...baseProps,
      created_room: {
        room_code: "ABC234",
        invite_url: "http://localhost/invites/raw-token",
        lobby_path: "/games/g1/lobby",
      },
    })
    expect(screen.getByLabelText("Invitation URL")).toHaveValue("http://localhost/invites/raw-token")
    expect(screen.getByRole("link", { name: "Enter lobby" })).toHaveAttribute("href", "/games/g1/lobby")
  })
})
```

- [ ] **Step 2: Run the test and verify failure**

Run: `rtk npm run test:ui -- assets/svelte/CreateGame.test.js`

Expected: FAIL because the paper wrapper and case radio do not exist.

- [ ] **Step 3: Write and pass the Classic capacity validation test**

Add to `games_test.exs`:

```elixir
test "rejects a one-Detective Classic room" do
  user = user_fixture()
  case_version = case_version_fixture()

  changeset =
    Games.change_game(Scope.for_user(user), %{
      title: "Head to head",
      case_version_id: case_version.id,
      max_detectives: 1
    })

  refute changeset.valid?
  assert "must be greater than or equal to 2" in errors_on(changeset).max_detectives
end
```

Run: `rtk mix test test/detective/games_test.exs`

Expected: FAIL because `Game.create_changeset/2` currently accepts one.

Change `greater_than_or_equal_to: 1` to `greater_than_or_equal_to: 2` in
`Game.create_changeset/2`. Update the invitation concurrency fixture to use
capacity two, accept two Detectives, reject a third, and assert the final active
Detective count equals two. Then rerun both files:

Run: `rtk mix test test/detective/games_test.exs test/detective/invitations_test.exs`

Expected: PASS.

- [ ] **Step 4: Implement the graphical form without changing event contracts**

Import `WoodFrame`, `PaperSheet`, and `StatusStamp`. Use `WoodFrame` for the
desk and `PaperSheet` with `id="create-game-document"` for the form. Replace the
case `<select>` with one labeled radio per `case_options` entry:

```svelte
{#each case_options as option (option.value)}
  <label class="noir-case-choice">
    <input
      type="radio"
      name="game[case_version_id]"
      value={option.value}
      checked={String(fields.case_version_id ?? "") === String(option.value)}
      required
    />
    <span class="font-serif font-semibold">{option.label}</span>
    <span class="text-sm leading-5">{option.description}</span>
  </label>
{/each}
```

Keep room title, maximum Detective, and invite expiry fields. Style the submit
as signal-red wax authority with visible focus and label it `Seal and create
room`. Render `global_error` as a danger `StatusStamp` plus adjacent readable
copy. Render `created_room` as a separate clipped dispatch paper with raw URL,
copy button, room code, and lobby link. Render maximum-Detective options from
`[2, 3, 4]` only.

- [ ] **Step 5: Run Svelte and LiveView tests**

Run: `rtk npm run test:ui -- assets/svelte/CreateGame.test.js`

Expected: PASS.

Run: `rtk mix test test/detective_web/live/game_new_live_test.exs`

Expected: PASS with unchanged form serialization and room creation.

- [ ] **Step 6: Commit**

```bash
rtk git add assets/svelte/CreateGame.svelte assets/svelte/CreateGame.test.js lib/detective/games/game.ex test/detective/games_test.exs test/detective/invitations_test.exs test/detective_web/live/game_new_live_test.exs
rtk git commit -m "feat(ui): style case-opening desk"
```

### Task 6: Turn Invite into a sealed summons

**Files:**
- Modify: `assets/svelte/Invite.svelte`
- Create: `assets/svelte/Invite.test.js`
- Modify: `test/detective_web/live/invite_live_test.exs`

**Interfaces:**
- Consumes: existing allow-listed `invite` and `error` props unchanged.
- Preserves: `#accept-game-invite`, `phx-click="accept_invite"`, and `#invite-back-dashboard`.

- [ ] **Step 1: Write failing Invite tests**

```javascript
import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import Invite from "./Invite.svelte"

const invite = {
  room_code: "ABC234",
  game_title: "Midnight Bureau",
  case_title: "The Pendleton Murders",
  host_name: "Elizabeth",
  detective_count: 1,
  max_detectives: 4,
  places_left: 3,
  membership_status: null,
}

describe("Invite", () => {
  it("renders a valid summons with an acceptance seal", () => {
    render(Invite, { invite, error: null })
    expect(document.querySelector("#invite-summons.noir-paper-sheet")).toBeInTheDocument()
    expect(screen.getByRole("button", { name: "Accept case invitation" })).toHaveAttribute(
      "id",
      "accept-game-invite",
    )
    expect(screen.getByText("1/4")).toBeInTheDocument()
  })

  it("stamps an unavailable invitation without an accept button", () => {
    render(Invite, { invite: null, error: "This invitation is no longer available." })
    expect(screen.getByText("Invitation closed")).toHaveClass("noir-status-stamp-danger")
    expect(screen.queryByRole("button", { name: /Accept/i })).not.toBeInTheDocument()
    expect(screen.getByRole("link", { name: "Back to dashboard" })).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and verify failure**

Run: `rtk npm run test:ui -- assets/svelte/Invite.test.js`

Expected: FAIL because the summons wrapper and acceptance name do not exist.

- [ ] **Step 3: Implement valid and closed summons states**

Use `WoodFrame` as the desk and `PaperSheet` as `#invite-summons`. Keep the
allow-listed room details in a semantic `dl`. Use an `aria-hidden` decorative
wax SVG adjacent to the semantic accept button. Give the button accessible name
`Accept case invitation`; visible text remains `Join as detective` or `Return
to room`. Render unavailable, full, or rejected copy with a danger stamp and
the existing `#invite-error` alert.

- [ ] **Step 4: Run Invite tests**

Run: `rtk npm run test:ui -- assets/svelte/Invite.test.js`

Expected: PASS.

Run: `rtk mix test test/detective_web/live/invite_live_test.exs`

Expected: PASS, including no token hash or case content in props.

- [ ] **Step 5: Commit**

```bash
rtk git add assets/svelte/Invite.svelte assets/svelte/Invite.test.js test/detective_web/live/invite_live_test.exs
rtk git commit -m "feat(ui): seal game invitations"
```

### Task 7: Turn Lobby into a player tray

**Files:**
- Modify: `assets/svelte/Lobby.svelte`
- Create: `assets/svelte/Lobby.test.js`
- Modify: `test/detective_web/live/lobby_live_test.exs`

**Interfaces:**
- Consumes: existing `lobby` prop and existing Phoenix Channel events.
- Uses: `PortraitToken` and `StatusStamp` from Task 1.
- Preserves: `applyLobby`, Presence reconciliation, ready/unready, idempotent start command, and redirect behavior.

- [ ] **Step 1: Write failing static lobby tests**

```javascript
import { render, screen } from "@testing-library/svelte"
import { describe, expect, it } from "vitest"
import Lobby from "./Lobby.svelte"

const lobby = {
  id: "g1",
  title: "Midnight Bureau",
  room_code: "ABC234",
  status: "waiting",
  phase: "lobby",
  max_detectives: 4,
  current_version: 0,
  case_title: "The Pendleton Murders",
  case_version: 1,
  membership: { id: "p1", role: "chisel", ready: false },
  players: [{ id: "p1", display_name: "Elizabeth", role: "chisel", ready: false, seat: null }],
}

describe("Lobby", () => {
  it("renders one Chisel tray and four Detective seats", () => {
    render(Lobby, { lobby })
    expect(screen.getByTestId("lobby-chisel-seat")).toHaveTextContent("Elizabeth")
    expect(screen.getAllByTestId(/lobby-detective-seat-/)).toHaveLength(4)
    expect(screen.getByTestId("lobby-detective-seat-1")).toHaveTextContent("Open seat")
  })

  it("keeps host start disabled without a ready Detective", () => {
    render(Lobby, { lobby })
    expect(screen.getByRole("button", { name: "Waiting for Detectives" })).toBeDisabled()
  })
})
```

- [ ] **Step 2: Run the test and verify failure**

Run: `rtk npm run test:ui -- assets/svelte/Lobby.test.js`

Expected: FAIL because fixed seat test IDs do not exist.

- [ ] **Step 3: Replace only Lobby markup with the player tray**

Keep the complete `<script>` block unchanged. Derive four visual slots with:

```javascript
let detectiveSlots = $derived(
  [1, 2, 3, 4].map((seat) => detectives.find((player) => player.seat === seat)),
)
```

Render:

- `#lobby-player-tray.noir-wood-frame` as the main board.
- `data-testid="lobby-chisel-seat"` for the Chisel slot.
- `data-testid="lobby-detective-seat-${seat}"` for all four fixed slots.
- `PortraitToken` for occupied slots and an inset empty recess for open slots.
- Ready and role `StatusStamp` components with readable text.
- Presence as a small lamp plus an `sr-only` Online or Offline label.
- Existing `#lobby-ready`, `#lobby-unready`, `#lobby-start-game`, and
  `#lobby-command-error` controls.

Do not use Presence to create or remove slots. `room.players` remains the only
membership source.

- [ ] **Step 4: Run Lobby tests**

Run: `rtk npm run test:ui -- assets/svelte/Lobby.test.js`

Expected: PASS.

Run: `rtk mix test test/detective_web/live/lobby_live_test.exs test/detective_web/channels/lobby_channel_test.exs`

Expected: PASS, including outsider rejection and allow-listed lobby props.

- [ ] **Step 5: Commit**

```bash
rtk git add assets/svelte/Lobby.svelte assets/svelte/Lobby.test.js test/detective_web/live/lobby_live_test.exs
rtk git commit -m "feat(ui): build tactile lobby tray"
```

### Task 8: Verify and polish the complete app journey

**Files:**
- Modify when required by observed defects: `assets/css/app.css`
- Modify when required by observed defects: files changed in Tasks 1-7

**Interfaces:**
- Consumes: all Task 1-7 screens.
- Produces: browser-verified desktop, tablet, and mobile behavior with no console warning.

- [ ] **Step 1: Run all automated gates**

Run: `rtk npm run test:ui`

Expected: all Vitest tests pass.

Run: `rtk mix assets.build`

Expected: client and SSR builds finish without warnings.

Run: `rtk mix precommit`

Expected: formatting, compilation, asset build, and all ExUnit tests pass.

- [ ] **Step 2: Invoke the Playwright skill and inspect the running app**

Start PostgreSQL and the development server only if not already running:

```bash
rtk docker compose -f docker-compose.dev.yml up -d postgres
rtk mix phx.server
```

Use Playwright with one anonymous context and one authenticated context. Check
`/`, `/users/register`, `/users/log-in`, `/dashboard`, `/games/new`, a valid
`/invites/:token`, and `/games/:id/lobby` at 1440x900, 1024x768, 844x390, and
390x844.

For every viewport verify:

- No horizontal page overflow.
- Keyboard focus is visible.
- Every form label still targets its input.
- Dashboard drawers navigate to lobby or game.
- Raw invite token appears only on the created-room sheet.
- Invite accept and Lobby ready/start still send the original events.
- Chisel and four Detective slots remain distinguishable.
- Browser console has zero warning and error entries.

- [ ] **Step 3: Apply observed fixes and rerun focused tests**

For each defect, first add or tighten the nearest Vitest or LiveView assertion,
verify failure, change the smallest component or CSS rule, then rerun that test.
Do not change context or Channel logic to fix a visual defect.

- [ ] **Step 4: Run final gates**

Run: `rtk npm run test:ui && rtk mix precommit`

Expected: both commands pass.

- [ ] **Step 5: Commit verified polish**

```bash
rtk git add assets/css/app.css assets/svelte/Home.svelte assets/svelte/Home.test.js assets/svelte/Dashboard.svelte assets/svelte/Dashboard.test.js assets/svelte/CreateGame.svelte assets/svelte/CreateGame.test.js assets/svelte/Invite.svelte assets/svelte/Invite.test.js assets/svelte/Lobby.svelte assets/svelte/Lobby.test.js assets/svelte/ui/WoodFrame.svelte assets/svelte/ui/PaperSheet.svelte assets/svelte/ui/StatusStamp.svelte assets/svelte/ui/PortraitToken.svelte assets/svelte/ui/NoirPrimitives.test.js lib/detective/games.ex lib/detective/games/game.ex lib/detective_web/components/layouts.ex lib/detective_web/components/layouts/root.html.heex lib/detective_web/components/core_components.ex lib/detective_web/live/home_live.ex lib/detective_web/live/dashboard_live.ex lib/detective_web/live/game_new_live.ex lib/detective_web/live/invite_live.ex lib/detective_web/live/lobby_live.ex lib/detective_web/live/user_live/login.ex lib/detective_web/live/user_live/registration.ex lib/detective_web/live/user_live/confirmation.ex lib/detective_web/live/user_live/settings.ex test/detective/games_test.exs test/detective/invitations_test.exs test/detective_web/live/home_live_test.exs test/detective_web/live/dashboard_live_test.exs test/detective_web/live/game_new_live_test.exs test/detective_web/live/invite_live_test.exs test/detective_web/live/lobby_live_test.exs test/detective_web/live/user_live/login_test.exs test/detective_web/live/user_live/registration_test.exs test/detective_web/live/user_live/settings_test.exs
rtk git diff --cached --name-only
rtk git commit -m "fix(ui): polish noir app journey"
```

Before committing, unstage any path not directly changed by Task 8. If browser
verification finds no defect and no tracked file changes, skip this commit.
