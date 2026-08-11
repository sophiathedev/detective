defmodule Detective.Games.PlayerNoteTest do
  use Detective.DataCase, async: true

  import Detective.AccountsFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope
  alias Detective.Games
  alias Detective.Games.PlayerNote

  test "notes are private to one active game member and support clearing" do
    host = user_fixture()
    outsider = user_fixture()
    %{game: game} = game_fixture(host)

    game
    |> Ecto.Changeset.change(status: "active", phase: "detective_turn")
    |> Repo.update!()

    assert {:ok, blank} = Games.get_player_note(Scope.for_user(host), game.id)
    assert blank.content == ""

    assert {:ok, saved} =
             Games.save_player_note(
               Scope.for_user(host),
               game.id,
               "The clerk contradicts the station ledger."
             )

    assert saved.content == "The clerk contradicts the station ledger."
    assert Repo.aggregate(PlayerNote, :count) == 1

    assert {:ok, restored} = Games.get_player_note(Scope.for_user(host), game.id)
    assert restored.content == saved.content

    assert {:ok, updated} =
             Games.save_player_note(Scope.for_user(host), game.id, "The ledger was planted.")

    assert updated.content == "The ledger was planted."
    assert Repo.aggregate(PlayerNote, :count) == 1

    assert {:error, :not_a_member} =
             Games.get_player_note(Scope.for_user(outsider), game.id)

    assert {:ok, cleared} = Games.save_player_note(Scope.for_user(host), game.id, "  ")
    assert cleared.content == ""
    assert Repo.aggregate(PlayerNote, :count) == 0
  end

  test "notes reject oversized content and waiting rooms" do
    host = user_fixture()
    %{game: game} = game_fixture(host)

    assert {:error, :notes_unavailable} =
             Games.get_player_note(Scope.for_user(host), game.id)

    game
    |> Ecto.Changeset.change(status: "active", phase: "detective_turn")
    |> Repo.update!()

    assert {:error, changeset} =
             Games.save_player_note(Scope.for_user(host), game.id, String.duplicate("x", 5_001))

    assert "should be at most 5000 character(s)" in errors_on(changeset).content
  end

  test "notes remain isolated between active members of the same game" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Detective.Invitations.accept(Scope.for_user(detective), token)

    game
    |> Ecto.Changeset.change(status: "active", phase: "detective_turn")
    |> Repo.update!()

    assert {:ok, host_note} =
             Games.save_player_note(Scope.for_user(host), game.id, "Chisel-only theory")

    assert {:ok, detective_note} =
             Games.save_player_note(Scope.for_user(detective), game.id, "Detective-only lead")

    assert host_note.user_id == host.id
    assert detective_note.user_id == detective.id

    assert {:ok, restored_host_note} = Games.get_player_note(Scope.for_user(host), game.id)

    assert {:ok, restored_detective_note} =
             Games.get_player_note(Scope.for_user(detective), game.id)

    assert restored_host_note.content == "Chisel-only theory"
    assert restored_detective_note.content == "Detective-only lead"
    assert Repo.aggregate(PlayerNote, :count) == 2
  end
end
