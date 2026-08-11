defmodule Detective.GamesTest do
  use Detective.DataCase, async: true

  import Detective.AccountsFixtures
  import Detective.CasesFixtures
  import Detective.GamesFixtures

  alias Detective.Accounts.Scope
  alias Detective.Games
  alias Detective.Games.{GameEvent, GamePlayer, GamePrivateEvent}
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

  test "a Detective can leave a waiting lobby and the public projection drops membership" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, %{player: player}} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{event: :player_left, player_id: player_id, lobby: lobby}} =
             Games.leave_lobby(Scope.for_user(detective), game.id, 0)

    assert player_id == player.id
    assert lobby.current_version == 1
    refute Enum.any?(lobby.players, &(&1.id == player.id))
    assert lobby.invite.status == "active"
    refute Map.has_key?(lobby.invite, :token_hash)
    assert {:error, :not_a_member} = Games.get_lobby(Scope.for_user(detective), game.id)
    assert Repo.get!(GamePlayer, player.id).status == "left"
  end

  test "the Chisel cannot leave and only the Chisel can remove an active Detective" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, %{player: player}} = Invitations.accept(Scope.for_user(detective), token)

    assert {:error, :not_detective} =
             Games.leave_lobby(Scope.for_user(host), game.id, 0)

    assert {:error, :not_chisel} =
             Games.remove_player(Scope.for_user(detective), game.id, player.id, 0)

    assert {:ok, %{event: :player_removed, player_id: player_id, lobby: lobby}} =
             Games.remove_player(Scope.for_user(host), game.id, player.id, 0)

    assert player_id == player.id
    assert lobby.current_version == 1
    refute Enum.any?(lobby.players, &(&1.id == player.id))
    assert Repo.get!(GamePlayer, player.id).status == "removed"
  end

  test "the Chisel cancels a waiting room and revokes its invitation atomically" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)

    assert {:error, :not_chisel} =
             Games.cancel_lobby(Scope.for_user(detective), game.id, 0)

    now = ~U[2026-08-07 03:00:00Z]

    assert {:ok, %{game_id: game_id, version: 1}} =
             Games.cancel_lobby(Scope.for_user(host), game.id, 0, now: now)

    assert game_id == game.id

    assert %{status: "cancelled", finished_at: ^now, finish_reason: "host_cancelled"} =
             Repo.get!(Detective.Games.Game, game.id)

    assert Repo.one!(GameInvite).revoked_at == now
    assert {:error, :game_not_waiting} = Games.cancel_lobby(Scope.for_user(host), game.id, 1)
    assert {:error, :game_not_waiting} = Invitations.preview(Scope.for_user(detective), token)
    assert {:error, :game_not_found} = Games.get_lobby(Scope.for_user(host), game.id)
  end

  test "cancelling a lobby rejects a stale version without changing the room" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:ok, %{lobby: lobby}} =
             Games.set_ready(Scope.for_user(detective), game.id, 0, true)

    assert lobby.current_version == 1

    assert {:error, :stale_version} =
             Games.cancel_lobby(Scope.for_user(host), game.id, 0)

    assert %{status: "waiting", current_version: 1, finished_at: nil} =
             Repo.get!(Detective.Games.Game, game.id)

    assert {:ok, current_lobby} = Games.get_lobby(Scope.for_user(host), game.id)
    assert current_lobby.current_version == 1
    assert current_lobby.invite.status == "active"
  end

  test "the Chisel updates only published case files and a capacity that fits the room" do
    host = user_fixture()
    detective = user_fixture()
    replacement_case = case_version_fixture()
    %{game: game, invite_token: token} = game_fixture(host, %{max_detectives: 4})
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    assert {:error, :not_chisel} =
             Games.update_lobby_settings(
               Scope.for_user(detective),
               game.id,
               %{case_version_id: replacement_case.id, max_detectives: 2},
               0
             )

    assert {:ok, %{event: :lobby_settings_updated, lobby: lobby}} =
             Games.update_lobby_settings(
               Scope.for_user(host),
               game.id,
               %{case_version_id: replacement_case.id, max_detectives: 2},
               0
             )

    assert lobby.case_version_id == replacement_case.id
    assert lobby.case_title == replacement_case.case_file.title
    assert lobby.max_detectives == 2
    assert lobby.current_version == 1
    assert Repo.one!(GameInvite).max_uses == 2
  end

  test "room capacity cannot be reduced below active Detective membership" do
    host = user_fixture()
    case_version = case_version_fixture()
    %{game: game, invite_token: token} = game_fixture(host, %{max_detectives: 4})

    Enum.each(1..3, fn _seat ->
      detective = user_fixture()
      assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)
    end)

    assert {:error, :capacity_below_membership} =
             Games.update_lobby_settings(
               Scope.for_user(host),
               game.id,
               %{case_version_id: case_version.id, max_detectives: 2},
               0
             )
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

  test "finished dashboard dossiers include compact result metadata" do
    user = user_fixture()
    %{game: game} = game_fixture(user, %{title: "Sealed File"})
    started_at = ~U[2026-08-07 01:00:00Z]
    finished_at = ~U[2026-08-07 02:30:00Z]

    game
    |> Ecto.Changeset.change(%{
      status: "finished",
      phase: "finished",
      started_at: started_at,
      finished_at: finished_at,
      winner_role: "chisel",
      winner_user_id: user.id,
      finish_reason: "time_expired"
    })
    |> Repo.update!()

    assert [%{won: true} = dossier] =
             Games.list_game_dossiers(Scope.for_user(user)).finished

    assert dossier.winner_role == "chisel"
    assert dossier.finish_reason == "time_expired"
    assert dossier.started_at == started_at
    assert dossier.finished_at == finished_at
    refute Map.has_key?(dossier, :case_content)
  end

  test "the Chisel creates one idempotent rematch from a finished game" do
    host = user_fixture()
    %{game: source, case_version: case_version} = game_fixture(host, %{title: "Cold Ledger"})

    source
    |> Ecto.Changeset.change(status: "finished", phase: "finished")
    |> Repo.update!()

    token = "fresh-rematch-token"

    assert {:ok, first} =
             Games.rematch(Scope.for_user(host), source.id,
               room_code: "REM234",
               invite_token: {token, :crypto.hash(:sha256, token)}
             )

    refute first.duplicate
    assert first.invite_token == token
    assert first.game.rematch_of_game_id == source.id
    assert first.game.case_version_id == case_version.id
    assert first.game.max_detectives == source.max_detectives
    assert first.game.host_user_id == host.id
    assert first.game.status == "waiting"

    assert {:ok, duplicate} = Games.rematch(Scope.for_user(host), source.id)
    assert duplicate.duplicate
    assert duplicate.invite_token == nil
    assert duplicate.game.id == first.game.id
    assert Repo.aggregate(Detective.Games.Game, :count) == 2
  end

  test "only the original Chisel can rematch a finished game" do
    host = user_fixture()
    detective = user_fixture()
    %{game: game, invite_token: token} = game_fixture(host)
    assert {:ok, _result} = Invitations.accept(Scope.for_user(detective), token)

    game
    |> Ecto.Changeset.change(status: "finished", phase: "finished")
    |> Repo.update!()

    assert {:error, :not_rematchable} =
             Games.rematch(Scope.for_user(detective), game.id)

    active = game_fixture(host).game
    assert {:error, :not_rematchable} = Games.rematch(Scope.for_user(host), active.id)
  end

  test "finished members page through only the public replay chronology" do
    host = user_fixture()
    outsider = user_fixture()
    %{game: game} = game_fixture(host)

    game
    |> Ecto.Changeset.change(status: "finished", phase: "finished")
    |> Repo.update!()

    events =
      Enum.map(1..31, fn sequence ->
        %GameEvent{
          game_id: game.id,
          command_id: Ecto.UUID.generate(),
          sequence: sequence,
          event_type: "player_moved",
          public_payload: %{"location_id" => "#{sequence}"}
        }
        |> GameEvent.insert_changeset()
        |> Repo.insert!()
      end)

    first_event = hd(events)

    %GamePrivateEvent{
      game_id: game.id,
      game_event_id: first_event.id,
      recipient_user_id: host.id,
      payload: %{"solution" => "must remain sealed"}
    }
    |> GamePrivateEvent.insert_changeset()
    |> Repo.insert!()

    assert {:ok, first_page} = Games.replay_page(Scope.for_user(host), game.id, 0)
    assert length(first_page.events) == 30
    assert first_page.has_next
    refute first_page.has_previous
    assert hd(first_page.events).sequence == 1
    refute Map.has_key?(hd(first_page.events), :private_payloads)
    refute Jason.encode!(first_page) =~ "must remain sealed"

    assert {:ok, second_page} = Games.replay_page(Scope.for_user(host), game.id, 1)
    assert Enum.map(second_page.events, & &1.sequence) == [31]
    refute second_page.has_next
    assert second_page.has_previous

    assert {:error, :replay_unavailable} =
             Games.replay_page(Scope.for_user(host), game.id, 2)

    assert {:error, :replay_unavailable} =
             Games.replay_page(Scope.for_user(host), game.id, 999_999_999_999)

    assert {:error, :replay_unavailable} =
             Games.replay_page(Scope.for_user(outsider), game.id, 0)
  end
end
