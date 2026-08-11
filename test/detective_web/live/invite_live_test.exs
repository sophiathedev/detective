defmodule DetectiveWeb.InviteLiveTest do
  use DetectiveWeb.ConnCase, async: true

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import LiveSvelte.Test
  import Phoenix.LiveViewTest

  alias Detective.Accounts.Scope
  alias Detective.Repo

  test "redirects guests to login before exposing invite details", %{conn: conn} do
    host = user_fixture()
    %{invite_token: token} = game_fixture(host)

    conn = get(conn, ~p"/invites/#{token}")

    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) == ~p"/invites/#{token}"
  end

  test "shows an allow-listed preview and accepts membership", %{conn: conn} do
    host = user_fixture(display_name: "Host Name")
    detective = user_fixture(display_name: "Detective Name")
    %{game: game, invite_token: token} = game_fixture(host)

    {:ok, view, _html} =
      conn
      |> log_in_user(detective)
      |> live(~p"/invites/#{token}")

    component = get_svelte(view, id: "invite-frontend")
    invite = component.props["invite"]
    assert invite["game_id"] == game.id
    assert invite["host_name"] == "Host Name"
    refute Map.has_key?(invite, "token_hash")
    refute Map.has_key?(invite, "content")

    DetectiveWeb.Endpoint.subscribe("lobby:#{game.id}")

    assert {:error, {:live_redirect, %{to: path}}} = render_click(view, "accept_invite")
    assert path == ~p"/games/#{game.id}/lobby"

    assert_receive %Phoenix.Socket.Broadcast{
      event: "lobby_state",
      payload: %{lobby: lobby, version: 0}
    }

    assert Enum.any?(lobby.players, &(&1.display_name == "Detective Name"))
  end

  test "does not reveal details for an invalid token", %{conn: conn} do
    detective = user_fixture()

    {:ok, view, _html} =
      conn
      |> log_in_user(detective)
      |> live(~p"/invites/not-a-real-token")

    component = get_svelte(view, id: "invite-frontend")
    assert component.props["invite"] == nil
    assert component.props["error"] == "This invitation is no longer available."
  end

  test "sends an existing member directly to the lobby", %{conn: conn} do
    host = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)

    {:ok, view, _html} =
      conn
      |> log_in_user(host)
      |> live(~p"/invites/#{token}")

    assert {:error, {:live_redirect, %{to: path}}} = render_click(view, "accept_invite")
    assert path == ~p"/games/#{game.id}/lobby"
  end

  test "shows a specific error when the room is full", %{conn: conn} do
    host = user_fixture()
    first_detective = user_fixture()
    second_detective = user_fixture()
    waiting_detective = user_fixture()
    %{invite_token: token, invite: invite} = game_fixture(host, %{max_detectives: 2})

    invite
    |> Ecto.Changeset.change(max_uses: 3)
    |> Repo.update!()

    assert {:ok, _result} = Detective.Invitations.accept(Scope.for_user(first_detective), token)
    assert {:ok, _result} = Detective.Invitations.accept(Scope.for_user(second_detective), token)

    {:ok, view, _html} =
      conn
      |> log_in_user(waiting_detective)
      |> live(~p"/invites/#{token}")

    component = get_svelte(view, id: "invite-frontend")
    assert component.props["invite"]["places_left"] == 0
    assert component.props["error"] == nil

    render_click(view, "accept_invite")

    component = get_svelte(view, id: "invite-frontend")
    assert component.props["error"] == "This room is full."
  end

  test "keeps a removed player out of the room", %{conn: conn} do
    host = user_fixture()
    detective = user_fixture()
    %{invite_token: token} = game_fixture(host)

    assert {:ok, %{player: player}} =
             Detective.Invitations.accept(Scope.for_user(detective), token)

    player
    |> Ecto.Changeset.change(status: "removed", ready: false)
    |> Repo.update!()

    {:ok, view, _html} =
      conn
      |> log_in_user(detective)
      |> live(~p"/invites/#{token}")

    component = get_svelte(view, id: "invite-frontend")
    assert component.props["invite"]["membership_status"] == "removed"

    render_click(view, "accept_invite")

    component = get_svelte(view, id: "invite-frontend")
    assert component.props["error"] == "You cannot join this room."
  end
end
