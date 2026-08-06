defmodule DetectiveWeb.LocaleController do
  use DetectiveWeb, :controller

  alias DetectiveWeb.Locale

  def update(conn, %{"locale" => locale} = params) do
    if Locale.supported?(locale) do
      conn
      |> put_session(:locale, locale)
      |> redirect(to: safe_return_to(params["return_to"]))
    else
      conn
      |> put_status(:unprocessable_entity)
      |> text("Unsupported locale")
    end
  end

  defp safe_return_to(return_to) when is_binary(return_to) do
    uri = URI.parse(return_to)

    if uri.scheme == nil && uri.host == nil && String.starts_with?(return_to, "/") &&
         !String.starts_with?(return_to, "//") do
      return_to
    else
      ~p"/"
    end
  end

  defp safe_return_to(_return_to), do: ~p"/"
end
