defmodule DetectiveWeb.UserLive.Login do
  use DetectiveWeb, :live_view

  alias Detective.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="noir-auth-desk px-4 py-12 sm:px-6 sm:py-20" aria-labelledby="login-title">
        <div id="auth-login-sheet" class="noir-paper-sheet mx-auto max-w-lg p-6 sm:p-10">
          <p class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--noir-red-700)]">
            Identity file
          </p>
          <h1
            id="login-title"
            class="mt-3 font-serif text-4xl font-semibold text-[var(--noir-ink-900)]"
          >
            Log in
          </h1>
          <p class="mt-3 text-sm leading-6 text-[#66513c]">
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Don't have an account? <.link
                navigate={~p"/users/register"}
                class="font-semibold text-[var(--noir-red-700)] hover:underline"
                phx-no-format
              >Sign up</.link> for an account now.
            <% end %>
          </p>

          <div
            :if={local_mail_adapter?()}
            class="mt-6 flex gap-3 border-l-2 border-[var(--noir-red-500)] bg-[#d8c7a5] px-4 py-3 text-sm text-[var(--noir-ink-900)]"
          >
            <.icon name="hero-information-circle" class="size-5 shrink-0" />
            <div>
              <p>You are running the local mail adapter.</p>
              <p>
                To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
              </p>
            </div>
          </div>

          <.form
            for={@form}
            id="login_form_magic"
            action={~p"/users/log-in"}
            phx-submit="submit_magic"
            class="mt-7"
          >
            <.input
              readonly={!!@current_scope}
              field={@form[:email]}
              id="login_form_magic_email"
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <.button variant="primary" class="noir-physical-button w-full px-4 text-sm font-semibold">
              Log in with email <span aria-hidden="true">→</span>
            </.button>
          </.form>

          <div class="my-6 flex items-center gap-3 font-mono text-xs uppercase tracking-[0.2em] text-[#715a42]">
            <span class="h-px flex-1 bg-[var(--noir-paper-500)]"></span>
            or <span class="h-px flex-1 bg-[var(--noir-paper-500)]"></span>
          </div>

          <.form
            for={@form}
            id="login_form_password"
            action={~p"/users/log-in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
          >
            <.input
              readonly={!!@current_scope}
              field={@form[:email]}
              id="login_form_password_email"
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              spellcheck="false"
            />
            <.button
              variant="primary"
              class="noir-physical-button w-full px-4 text-sm font-semibold"
              name={@form[:remember_me].name}
              value="true"
            >
              Log in and stay logged in <span aria-hidden="true">→</span>
            </.button>
            <.button class="mt-2 w-full border border-[var(--noir-ink-900)] bg-transparent px-4 py-2.5 text-sm font-semibold text-[var(--noir-ink-900)] transition hover:bg-[var(--noir-ink-900)] hover:text-[var(--noir-paper-100)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--noir-red-700)]">
              Log in only this time
            </.button>
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:detective, Detective.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
