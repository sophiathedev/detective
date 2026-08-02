defmodule Detective.InvitationsTest do
  use Detective.DataCase, async: true

  import Detective.AccountsFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope
  alias Detective.Games.GamePlayer
  alias Detective.Invitations

  test "previews allow-listed room data and accepts a detective" do
    host = user_fixture(display_name: "Host Name")
    detective = user_fixture(display_name: "Guest Name")
    %{game: game, invite_token: token} = game_fixture(host)

    assert {:ok, preview} = Invitations.preview(Scope.for_user(detective), token)
    assert preview.game_id == game.id
    assert preview.host_name == "Host Name"
    assert preview.detective_count == 0
    assert preview.places_left == 2
    refute Map.has_key?(preview, :token_hash)
    refute Map.has_key?(preview, :content)

    assert {:ok, %{player: player}} = Invitations.accept(Scope.for_user(detective), token)
    assert player.role == "detective"
    refute player.ready
    assert player.seat == 1
  end

  test "does not add one user twice" do
    host = user_fixture()
    detective = user_fixture()
    %{invite_token: token} = game_fixture(host)
    scope = Scope.for_user(detective)

    assert {:ok, _result} = Invitations.accept(scope, token)
    assert {:error, :already_a_member} = Invitations.accept(scope, token)
  end

  test "rejects expired invites" do
    now = DateTime.utc_now(:second)
    host = user_fixture()
    detective = user_fixture()

    %{invite_token: token} =
      game_fixture(host, %{}, now: DateTime.add(now, -25, :hour))

    assert {:error, :invite_expired} =
             Invitations.accept(Scope.for_user(detective), token, now: now)
  end

  test "only one detective takes the last place" do
    host = user_fixture()
    first = user_fixture()
    second = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host, %{max_detectives: 1})

    assert {:ok, _result} = Invitations.accept(Scope.for_user(first), token)
    assert {:error, reason} = Invitations.accept(Scope.for_user(second), token)
    assert reason in [:invite_exhausted, :room_full]

    assert Repo.aggregate(
             from(player in GamePlayer,
               where:
                 player.game_id == ^game.id and player.role == "detective" and
                   player.status == "active"
             ),
             :count
           ) == 1
  end
end
