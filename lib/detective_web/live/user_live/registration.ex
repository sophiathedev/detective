defmodule DetectiveWeb.UserLive.Registration do
  use DetectiveWeb, :live_view

  alias Detective.Accounts
  alias Detective.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section
        class="noir-auth-desk px-4 py-12 sm:px-6 sm:py-20"
        aria-labelledby="registration-title"
      >
        <div
          id="auth-registration-sheet"
          class="noir-paper-sheet mx-auto max-w-lg p-6 sm:p-10"
        >
          <p class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--noir-red-700)]">
            {gettext("New investigator record")}
          </p>
          <h1
            id="registration-title"
            class="mt-3 font-serif text-4xl font-semibold text-[var(--noir-ink-900)]"
          >
            {gettext("Register an investigator")}
          </h1>
          <p class="mt-3 text-sm leading-6 text-[#66513c]">
            {gettext("Already registered?")}
            <.link
              navigate={~p"/users/log-in"}
              class="font-semibold text-[var(--noir-red-700)] hover:underline"
            >
              {gettext("Log in")}
            </.link>
            {gettext("to reopen your file.")}
          </p>

          <.form
            for={@form}
            id="registration_form"
            phx-submit="save"
            phx-change="validate"
            class="mt-7"
          >
            <.input
              field={@form[:display_name]}
              type="text"
              label={gettext("Display name")}
              autocomplete="name"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              spellcheck="false"
              required
            />

            <.button
              variant="primary"
              phx-disable-with={gettext("Creating account...")}
              class="noir-physical-button w-full px-4 text-sm font-semibold"
            >
              {gettext("Create an account")}
            </.button>
          </.form>
          <p class="mt-6 border-t border-[var(--noir-paper-500)] pt-5 text-xs leading-5 text-[#705a42]">
            {gettext("Your display name is public inside a room. Your email remains account-only.")}
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: DetectiveWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext(
             "An email was sent to %{email}, please access it to confirm your account.",
             email: user.email
           )
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
