defmodule Detective.InvitationsTest do
  use Detective.DataCase, async: true

  import Detective.AccountsFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope
  alias Detective.Games
  alias Detective.Games.GamePlayer
  alias Detective.Invitations
  alias Detective.Invitations.GameInvite

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

  test "a Detective who left may rejoin, while a removed Detective stays barred" do
    host = user_fixture()
    detective = user_fixture()
    removed_detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host, %{max_detectives: 3})

    assert {:ok, %{player: first_player}} =
             Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, _result} = Games.leave_lobby(Scope.for_user(detective), game.id, 0)

    assert {:ok, %{player: rejoined_player}} =
             Invitations.accept(Scope.for_user(detective), token)

    assert rejoined_player.id == first_player.id
    assert rejoined_player.status == "active"
    assert rejoined_player.seat == 1

    assert {:ok, %{player: removed_player}} =
             Invitations.accept(Scope.for_user(removed_detective), token)

    assert {:ok, _result} =
             Games.remove_player(
               Scope.for_user(host),
               game.id,
               removed_player.id,
               1
             )

    assert {:error, :removed_from_game} =
             Invitations.accept(Scope.for_user(removed_detective), token)
  end

  test "the Chisel can revoke the current invitation" do
    now = DateTime.utc_now(:second)
    host = user_fixture()
    outsider = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)

    assert {:error, :not_chisel} =
             Invitations.revoke(Scope.for_user(outsider), game.id, 0, now: now)

    assert {:ok, %{version: 1, revoked_count: 1}} =
             Invitations.revoke(Scope.for_user(host), game.id, 0, now: now)

    assert Invitations.lobby_status(game.id, now: now).status == "revoked"
    assert {:error, :invite_revoked} = Invitations.preview(Scope.for_user(outsider), token)

    assert {:error, :invite_not_active} =
             Invitations.revoke(Scope.for_user(host), game.id, 1, now: now)
  end

  test "regenerating revokes the old token and returns a one-time raw replacement" do
    now = DateTime.utc_now(:second)
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: old_token} = game_fixture(host)
    new_token = "replacement-raw-token"
    new_hash = :crypto.hash(:sha256, new_token)

    assert {:ok, %{token: ^new_token, invite: invite, version: 1}} =
             Invitations.regenerate(
               Scope.for_user(host),
               game.id,
               0,
               6,
               now: now,
               invite_token: {new_token, new_hash}
             )

    assert invite.token_hash == new_hash
    assert invite.expires_at == DateTime.add(now, 6, :hour)
    refute Map.has_key?(Invitations.lobby_status(game.id, now: now), :token_hash)
    assert Invitations.lobby_status(game.id, now: now).status == "active"

    old_invite = Repo.get_by!(GameInvite, token_hash: :crypto.hash(:sha256, old_token))
    refute is_nil(old_invite.revoked_at)
    assert {:error, :invite_revoked} = Invitations.accept(Scope.for_user(detective), old_token)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), new_token)
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
    third = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host, %{max_detectives: 2})

    assert {:ok, _result} = Invitations.accept(Scope.for_user(first), token)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(second), token)
    assert {:error, reason} = Invitations.accept(Scope.for_user(third), token)
    assert reason in [:invite_exhausted, :room_full]

    assert Repo.aggregate(
             from(player in GamePlayer,
               where:
                 player.game_id == ^game.id and player.role == "detective" and
                   player.status == "active"
             ),
             :count
           ) == 2
  end
end
