defmodule DetectiveWeb.Locale do
  @moduledoc """
  Keeps the browser session, Gettext process locale, and LiveView locale in sync.
  """

  import Plug.Conn

  @behaviour Plug

  @supported_locales ~w(en vi)
  @default_locale "en"

  def supported_locales, do: @supported_locales

  def supported?(locale), do: locale in @supported_locales

  def normalize(locale) when locale in @supported_locales, do: locale
  def normalize(_locale), do: @default_locale

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    locale = get_session(conn, :locale) || preferred_locale(conn)
    locale = normalize(locale)

    Gettext.put_locale(DetectiveWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = normalize(session["locale"])
    Gettext.put_locale(DetectiveWeb.Gettext, locale)

    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp preferred_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> case do
      value when is_binary(value) ->
        if Regex.match?(~r/(^|,)\s*vi(?:-|;|,|$)/i, value), do: "vi", else: @default_locale

      _other ->
        @default_locale
    end
  end
end
