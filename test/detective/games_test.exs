defmodule Detective.GamesTest do
  use Detective.DataCase, async: true

  import Detective.AccountsFixtures
  import Detective.CasesFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope
  alias Detective.Games
  alias Detective.Games.GamePlayer
  alias Detective.Invitations
  alias Detective.Invitations.GameInvite

  test "creates a waiting game, one Chisel, and a hashed invite" do
    user = user_fixture()
    case_version = case_version_fixture()
    raw_token = "one-time-raw-token"
    token_hash = :crypto.hash(:sha256, raw_token)

    assert {:ok, result} =
             Games.create_game(
               Scope.for_user(user),
               %{
                 title: "The Midnight Desk",
                 case_version_id: case_version.id,
                 max_detectives: 3,
                 invite_hours: 6
               },
               room_code: "N0IR23" |> String.replace("0", "2"),
               invite_token: {raw_token, token_hash}
             )

    assert result.game.status == "waiting"
    assert result.game.phase == "lobby"
    assert result.invite_token == raw_token
    assert result.invite.token_hash == token_hash
    refute result.invite.token_hash == raw_token

    assert [%GamePlayer{user_id: user_id, role: "chisel", ready: true}] =
             Repo.all(GamePlayer)

    assert user_id == user.id
    assert Repo.aggregate(GameInvite, :count) == 1
  end

  test "rejects a case version that is not published" do
    user = user_fixture()
    draft_case = case_file_fixture(status: "draft")
    draft_version = case_version_fixture(case_file: draft_case)

    assert {:error, :case_version_not_published} =
             Games.create_game(Scope.for_user(user), %{
               title: "Invalid room",
               case_version_id: draft_version.id,
               max_detectives: 2
             })
  end

  test "enforces detective capacity bounds" do
    user = user_fixture()
    case_version = case_version_fixture()

    assert {:error, changeset} =
             Games.create_game(
               Scope.for_user(user),
               %{
                 title: "Crowded room",
                 case_version_id: case_version.id,
                 max_detectives: 5
               },
               room_code: "ROOM25"
             )

    assert "must be less than or equal to 4" in errors_on(changeset).max_detectives
  end

  test "rejects a one-Detective Classic room" do
    user = user_fixture()
    case_version = case_version_fixture()

    changeset =
      Games.change_game(Scope.for_user(user), %{
        title: "Head to head",
        case_version_id: case_version.id,
        max_detectives: 1
      })

    refute changeset.valid?
    assert "must be greater than or equal to 2" in errors_on(changeset).max_detectives
  end

  test "detective readiness is versioned and rejects stale commands" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{event: :player_ready, lobby: ready_lobby}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    assert ready_lobby.current_version == 1
    assert ready_lobby.membership.ready

    assert {:error, :stale_version} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, false)

    assert {:ok, %{event: :player_unready, lobby: unready_lobby}} =
             Games.set_ready(Scope.for_user(detective), game.id, 1, false)

    assert unready_lobby.current_version == 2
    refute unready_lobby.membership.ready
  end

  test "only active detectives can change readiness" do
    host = user_fixture()
    %{game: game} = game_fixture(host)

    assert {:error, :not_detective} =
             Games.set_ready(Scope.for_user(host), game.id, 0, true)

    assert {:error, :invalid_game_id} =
             Games.set_ready(Scope.for_user(host), "not-a-uuid", 0, true)
  end

  test "counts paused games in the active dashboard bucket" do
    user = user_fixture()
    %{game: game} = game_fixture(user)

    game
    |> Ecto.Changeset.change(status: "paused")
    |> Repo.update!()

    assert Games.game_summary(Scope.for_user(user)) == %{
             waiting: 0,
             active: 1,
             finished: 0
           }
  end

  test "lists only active memberships as allow-listed dashboard dossiers" do
    user = user_fixture()
    outsider = user_fixture()
    %{game: own_game} = game_fixture(user, %{title: "Own File", max_detectives: 3})
    %{game: other_game} = game_fixture(outsider, %{title: "Secret File"})

    dossiers = Games.list_game_dossiers(Scope.for_user(user))

    assert [%{id: id, title: "Own File", role: "chisel", max_detectives: 3}] = dossiers.waiting
    assert id == own_game.id
    refute Enum.any?(dossiers.waiting, &(&1.id == other_game.id))
    refute Map.has_key?(hd(dossiers.waiting), :case_content)
  end
end
