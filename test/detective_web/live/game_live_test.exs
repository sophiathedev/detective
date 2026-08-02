defmodule DetectiveWeb.GameLiveTest do
  use DetectiveWeb.ConnCase, async: false

  import Detective.AccountsFixtures
  import Detective.GamesFixtures
  import Phoenix.LiveViewTest

  alias Detective.Accounts.Scope
  alias Detective.Games.SessionSupervisor
  alias Detective.{Games, Invitations}

  test "active member opens the graphical casebook", %{conn: conn} do
    %{host: host, game: game} = active_game()
    conn = log_in_user(conn, host)

    assert {:ok, view, _html} = live(conn, ~p"/games/#{game.id}")
    assert has_element?(view, "#game-book-frontend")
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
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)
    assert {:ok, %{lobby: lobby}} = Games.set_ready(Scope.for_user(detective), game.id, 0, true)

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
