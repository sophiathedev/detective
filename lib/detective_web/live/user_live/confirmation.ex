defmodule DetectiveWeb.UserLive.Confirmation do
  use DetectiveWeb, :live_view

  alias Detective.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section
        class="noir-auth-desk px-4 py-12 sm:px-6 sm:py-20"
        aria-labelledby="confirmation-title"
      >
        <div
          id="auth-confirmation-sheet"
          class="noir-paper-sheet mx-auto max-w-lg p-6 sm:p-10"
        >
          <p class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--noir-red-700)]">
            Identity verification
          </p>
          <h1
            id="confirmation-title"
            class="mt-3 font-serif text-3xl font-semibold text-[var(--noir-ink-900)]"
          >
            Welcome {@user.email}
          </h1>
          <p class="mt-3 text-sm leading-6 text-[#66513c]">
            Confirm this sealed link to finish opening your investigator record.
          </p>

          <.form
            :if={!@user.confirmed_at}
            for={@form}
            id="confirmation_form"
            phx-mounted={JS.focus_first()}
            phx-submit="submit"
            action={~p"/users/log-in?_action=confirmed"}
            phx-trigger-action={@trigger_submit}
            class="mt-7"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Confirming..."
              class="noir-physical-button w-full px-4 text-sm font-semibold"
            >
              Confirm and stay logged in
            </.button>
            <.button
              phx-disable-with="Confirming..."
              class="mt-2 w-full border border-[var(--noir-ink-900)] bg-transparent px-4 py-2.5 text-sm font-semibold text-[var(--noir-ink-900)] transition hover:bg-[var(--noir-ink-900)] hover:text-[var(--noir-paper-100)]"
            >
              Confirm and log in only this time
            </.button>
          </.form>

          <.form
            :if={@user.confirmed_at}
            for={@form}
            id="login_form"
            phx-submit="submit"
            phx-mounted={JS.focus_first()}
            action={~p"/users/log-in"}
            phx-trigger-action={@trigger_submit}
            class="mt-7"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <%= if @current_scope do %>
              <.button
                phx-disable-with="Logging in..."
                class="noir-physical-button w-full px-4 text-sm font-semibold"
              >
                Log in
              </.button>
            <% else %>
              <.button
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with="Logging in..."
                class="noir-physical-button w-full px-4 text-sm font-semibold"
              >
                Keep me logged in on this device
              </.button>
              <.button
                phx-disable-with="Logging in..."
                class="mt-2 w-full border border-[var(--noir-ink-900)] bg-transparent px-4 py-2.5 text-sm font-semibold text-[var(--noir-ink-900)] transition hover:bg-[var(--noir-ink-900)] hover:text-[var(--noir-paper-100)]"
              >
                Log me in only this time
              </.button>
            <% end %>
          </.form>

          <p
            :if={!@user.confirmed_at}
            class="mt-8 border-l-2 border-[var(--noir-red-500)] bg-[#d8c7a5] px-4 py-3 text-sm text-[var(--noir-ink-900)]"
          >
            Tip: If you prefer passwords, you can enable them in the user settings.
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
