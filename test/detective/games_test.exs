defmodule Detective.GamesTest do
  use Detective.DataCase, async: true

  import Detective.AccountsFixtures
  import Detective.CasesFixtures

  alias Detective.Accounts.Scope
  alias Detective.Games
  alias Detective.Games.GamePlayer
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
end
