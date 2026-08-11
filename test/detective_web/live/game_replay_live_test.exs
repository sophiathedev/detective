defmodule DetectiveWeb.GameReplayLiveTest do
  use DetectiveWeb.ConnCase, async: true

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import Phoenix.LiveViewTest

  alias Detective.Games.{GameEvent, GamePlayer}
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

  test "renders every public event family and pages the chronology", %{conn: conn} do
    host = user_fixture(display_name: "Case Lead")
    %{game: game} = game_fixture(host)
    player = Repo.get_by!(GamePlayer, game_id: game.id, user_id: host.id)

    game
    |> Ecto.Changeset.change(%{
      status: "finished",
      phase: "finished",
      winner_role: "detective",
      winner_user_id: host.id,
      finish_reason: "case_solved"
    })
    |> Repo.update!()

    event_specs = [
      {"detective_placed", %{"player_id" => player.id, "location_id" => "51"}},
      {"player_moved",
       %{
         "player_id" => player.id,
         "from_location_id" => "51",
         "location_id" => "96"
       }},
      {"location_searched",
       %{"player_id" => player.id, "target_type" => "location", "target_id" => "51"}},
      {"suspect_searched",
       %{
         "player_id" => player.id,
         "target_type" => "suspect",
         "target_id" => "night-clerk"
       }},
      {"interrogation_started",
       %{"player_id" => player.id, "suspect_id" => "night-clerk", "topic_code" => "A"}},
      {"response_published", %{"chisel_player_id" => player.id}},
      {"challenge_succeeded", %{"detective_player_id" => player.id}},
      {"challenge_failed", %{"detective_player_id" => player.id}},
      {"accusation_submitted", %{"player_id" => player.id}},
      {"accusation_rejected", %{}},
      {"final_guess_submitted", %{}},
      {"game_finished", %{}},
      {"game_paused", %{}},
      {"game_resumed", %{}},
      {"turn_started", %{}},
      {"turn_ended", %{}},
      {"day_advanced", %{}},
      {"custom_public_event", %{}}
    ]

    events =
      (event_specs ++ List.duplicate({"custom_public_event", %{}}, 31 - length(event_specs)))
      |> Enum.with_index(1)
      |> Enum.map(fn {{event_type, public_payload}, sequence} ->
        %GameEvent{
          game_id: game.id,
          command_id: Ecto.UUID.generate(),
          sequence: sequence,
          event_type: event_type,
          public_payload: public_payload
        }
        |> GameEvent.insert_changeset()
        |> Repo.insert!()
      end)

    {:ok, view, _html} =
      conn
      |> log_in_user(host)
      |> live(~p"/games/#{game.id}/replay")

    assert has_element?(view, "#replay-next-page:not([disabled])")
    refute has_element?(view, "#replay-previous-page:not([disabled])")

    view
    |> element("#replay-next-page")
    |> render_click()

    assert has_element?(view, "#replay-previous-page:not([disabled])")
    assert has_element?(view, "#events-#{List.last(events).id}")
  end
end
