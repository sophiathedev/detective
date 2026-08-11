defmodule DetectiveWeb.GameReplayLiveTest do
  use DetectiveWeb.ConnCase, async: true

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import Phoenix.LiveViewTest

  alias Detective.Games.GameEvent
  alias Detective.Repo

  test "requires an authenticated user", %{conn: conn} do
    game_id = Ecto.UUID.generate()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/games/#{game_id}/replay")
  end

  test "renders a paged public chronology for a finished member", %{conn: conn} do
    host = user_fixture()
    %{game: game} = game_fixture(host, %{title: "The Closed Ledger"})

    game
    |> Ecto.Changeset.change(%{
      status: "finished",
      phase: "finished",
      winner_role: "chisel",
      winner_user_id: host.id,
      finish_reason: "time_expired"
    })
    |> Repo.update!()

    %GameEvent{
      game_id: game.id,
      command_id: Ecto.UUID.generate(),
      sequence: 1,
      event_type: "game_started",
      public_payload: %{}
    }
    |> GameEvent.insert_changeset()
    |> Repo.insert!()

    {:ok, view, _html} =
      conn
      |> log_in_user(host)
      |> live(~p"/games/#{game.id}/replay")

    assert has_element?(view, "#replay-shell")
    assert has_element?(view, "#replay-events > article")
    assert has_element?(view, "#replay-next-page[disabled]")
    assert has_element?(view, "#replay-back-to-result[href='/games/#{game.id}']")
  end

  test "does not expose another game's chronology", %{conn: conn} do
    host = user_fixture()
    outsider = user_fixture()
    %{game: game} = game_fixture(host)

    game
    |> Ecto.Changeset.change(status: "finished", phase: "finished")
    |> Repo.update!()

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
             conn
             |> log_in_user(outsider)
             |> live(~p"/games/#{game.id}/replay")
  end

  test "ignores an out-of-range page request without replacing the chronology", %{conn: conn} do
    host = user_fixture()
    %{game: game} = game_fixture(host)

    game
    |> Ecto.Changeset.change(status: "finished", phase: "finished")
    |> Repo.update!()

    %GameEvent{
      game_id: game.id,
      command_id: Ecto.UUID.generate(),
      sequence: 1,
      event_type: "game_started",
      public_payload: %{}
    }
    |> GameEvent.insert_changeset()
    |> Repo.insert!()

    {:ok, view, _html} =
      conn
      |> log_in_user(host)
      |> live(~p"/games/#{game.id}/replay")

    assert has_element?(view, "#replay-events > article")
    render_click(view, "replay_page", %{"page" => "999999999999"})
    assert has_element?(view, "#replay-events > article")
    assert has_element?(view, "#replay-next-page[disabled]")
  end
end
