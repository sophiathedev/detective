defmodule DetectiveWeb.LocaleControllerTest do
  use DetectiveWeb.ConnCase, async: true

  test "persists a supported locale and returns to an internal path", %{conn: conn} do
    conn = post(conn, ~p"/locale/vi?return_to=/users/log-in")

    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :locale) == "vi"

    conn = get(recycle(conn), ~p"/users/log-in")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert Enum.count(LazyHTML.filter(document, "html[lang='vi']")) == 1
    locale_link = LazyHTML.query(document, "#locale-vi")
    assert LazyHTML.attribute(locale_link, "aria-current") == ["true"]
  end

  test "rejects unsupported locales", %{conn: conn} do
    conn = post(conn, ~p"/locale/fr")

    assert response(conn, 422) == "Unsupported locale"
    assert get_session(conn, :locale) == "en"
  end

  test "does not redirect to an external return path", %{conn: conn} do
    conn = post(conn, ~p"/locale/vi?return_to=https://example.com/steal-session")

    assert redirected_to(conn) == ~p"/"
  end

  test "uses Vietnamese when the browser prefers it", %{conn: conn} do
    conn = conn |> put_req_header("accept-language", "en-US;q=0.7, vi-VN;q=0.9") |> get(~p"/")
    document = conn |> html_response(200) |> LazyHTML.from_document()

    assert get_session(conn, :locale) == "vi"
    assert Enum.count(LazyHTML.filter(document, "html[lang='vi']")) == 1
    locale_link = LazyHTML.query(document, "#locale-vi")
    assert LazyHTML.attribute(locale_link, "aria-current") == ["true"]
  end
end
