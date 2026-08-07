defmodule DetectiveWeb.GameLiveTest do
  use DetectiveWeb.ConnCase, async: false

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import LiveSvelte.Test
  import Phoenix.LiveViewTest

  alias Detective.Accounts.Scope
  alias Detective.Games.{Session, SessionSupervisor, State}
  alias Detective.{Games, Invitations}

  test "active member opens the graphical casebook", %{conn: conn} do
    %{host: host, game: game} = active_game()
    conn = log_in_user(conn, host)

    assert {:ok, view, _html} = live(conn, ~p"/games/#{game.id}")
    assert has_element?(view, "#game-book-frontend")
  end

  test "paused member opens the graphical casebook", %{conn: conn} do
    %{detective: detective, game: game} = active_game()
    {:ok, state} = Session.get_state(game.id)
    detective_player = State.player_by_user_id(state, detective.id)

    assert {:ok, _reply} =
             Session.pause_for_disconnect(game.id, [detective_player.id])

    assert {:ok, view, _html} =
             conn
             |> log_in_user(detective)
             |> live(~p"/games/#{game.id}")

    assert has_element?(view, "#game-book-frontend")
  end

  test "finished member reopens the graphical verdict from the archive", %{conn: conn} do
    %{detective: detective, game: game} = active_game()
    {:ok, session_pid} = SessionSupervisor.ensure_session(game.id)

    :sys.replace_state(session_pid, fn state ->
      detective_player = State.player_by_user_id(state, detective.id)

      %{
        state
        | status: :finished,
          phase: :finished,
          current_detective_id: nil,
          winner: %{
            "role" => "detective",
            "player_id" => detective_player.id,
            "reason" => "case_solved"
          }
      }
    end)

    assert {:ok, view, _html} =
             conn
             |> log_in_user(detective)
             |> live(~p"/games/#{game.id}")

    component = get_svelte(view, id: "game-book-frontend")
    public = component.props["initial_public"]

    assert public["status"] == "finished"
    assert public["result"]["solution"]["suspect_name"] == "Night Clerk"

    assert public["result"]["winner"]["player_id"] ==
             State.player_by_user_id(:sys.get_state(session_pid), detective.id).id
  end

  test "detective frontend receives only its allow-listed private projection", %{conn: conn} do
    %{detective: detective, game: game} = active_game()

    assert {:ok, view, _html} =
             conn
             |> log_in_user(detective)
             |> live(~p"/games/#{game.id}")

    component = get_svelte(view, id: "game-book-frontend")
    private = component.props["initial_private"]
    public = component.props["initial_public"]

    assert component.props["locale"] == "en"
    assert is_binary(component.props["csrf_token"])
    assert component.props["csrf_token"] != ""
    refute Map.has_key?(public, "solution")
    refute Map.has_key?(private, "response_options")
    refute Map.has_key?(private, "chisel_notes")
    assert is_list(private["available_actions"])
  end

  test "waiting game and outsider fail closed", %{conn: conn} do
    host = user_fixture()
    outsider = user_fixture()
    %{game: waiting_game} = game_fixture(host)

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             conn
             |> log_in_user(host)
             |> live(~p"/games/#{waiting_game.id}")

    %{game: active_game} = active_game()

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             build_conn()
             |> log_in_user(outsider)
             |> live(~p"/games/#{active_game.id}")
  end

  defp active_game do
    host = user_fixture()
    detective = user_fixture()
    second_detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(second_detective), token)

    assert {:ok, %{lobby: first_ready}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    assert {:ok, %{lobby: lobby}} =
             Games.set_ready(
               Scope.for_user(second_detective),
               game.id,
               first_ready.current_version,
               true
             )

    assert {:ok, _result} =
             Games.start_game(
               Scope.for_user(host),
               game.id,
               Ecto.UUID.generate(),
               lobby.current_version
             )

    on_exit(fn ->
      case Registry.lookup(Detective.GameRegistry, game.id) do
        [{pid, _value}] -> DynamicSupervisor.terminate_child(SessionSupervisor, pid)
        [] -> :ok
      end
    end)

    %{host: host, detective: detective, game: game}
  end
end
