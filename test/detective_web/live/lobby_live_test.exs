defmodule DetectiveWeb.LobbyLiveTest do
  use DetectiveWeb.ConnCase, async: true

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import LiveSvelte.Test
  import Phoenix.LiveViewTest

  test "renders only member lobby projection", %{conn: conn} do
    host = user_fixture(display_name: "Host Name")
    %{game: game} = game_fixture(host)

    {:ok, view, _html} = conn |> log_in_user(host) |> live(~p"/games/#{game.id}/lobby")

    component = get_svelte(view, id: "lobby-frontend")
    lobby = component.props["lobby"]
    assert lobby["id"] == game.id
    assert [%{"display_name" => "Host Name", "role" => "chisel"}] = lobby["players"]
    assert [%{"value" => case_version_id}] = component.props["case_options"]
    assert case_version_id == lobby["case_version_id"]
    assert lobby["invite"]["status"] == "active"
    refute Map.has_key?(lobby["invite"], "token_hash")
    refute Map.has_key?(lobby, "case_content")
    assert component.props["invite_url"] == nil
  end

  test "rejects a user outside the room", %{conn: conn} do
    host = user_fixture()
    outsider = user_fixture()
    %{game: game} = game_fixture(host)

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn
             |> log_in_user(outsider)
             |> live(~p"/games/#{game.id}/lobby")
  end
end
