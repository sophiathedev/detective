defmodule Detective.Invitations do
  @moduledoc """
  Hashed room invitations and capacity-safe acceptance.
  """

  import Ecto.Query, warn: false

  alias Detective.Accounts.Scope
  alias Detective.Games.{Game, GamePlayer}
  alias Detective.Invitations.GameInvite
  alias Detective.Repo

  @allowed_invite_hours [1, 6, 24, 72]

  def generate_token do
    token =
      :crypto.strong_rand_bytes(32)
      |> Base.url_encode64(padding: false)

    {token, token_hash(token)}
  end

  def lobby_status(game_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))

    case latest_invite(game_id) do
      nil ->
        %{status: "unavailable", expires_at: nil, uses_remaining: 0}

      invite ->
        %{
          status: invite_status(invite, now),
          expires_at: invite.expires_at,
          uses_remaining: max(invite.max_uses - invite.use_count, 0)
        }
    end
  end

  def revoke(scope, game_id, expected_version, opts \\ [])

  def revoke(%Scope{user: user}, game_id, expected_version, opts)
      when is_integer(expected_version) and expected_version >= 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))

    with {:ok, game_id} <- cast_game_id(game_id) do
      Repo.transact(fn ->
        game = locked_game(game_id)

        with %Game{} <- game,
             :ok <- validate_lobby_admin(game, user.id, expected_version),
             true <- active_invite_exists?(game.id, now) do
          {revoked_count, _invites} =
            GameInvite
            |> where(
              [invite],
              invite.game_id == ^game.id and is_nil(invite.revoked_at) and
                invite.expires_at > ^now and invite.use_count < invite.max_uses
            )
            |> Repo.update_all(set: [revoked_at: now, updated_at: now])

          updated_game = increment_game_version!(game)
          {:ok, %{version: updated_game.current_version, revoked_count: revoked_count}}
        else
          nil -> {:error, :game_not_found}
          false -> {:error, :invite_not_active}
          {:error, reason} -> {:error, reason}
        end
      end)
    else
      :error -> {:error, :invalid_game_id}
    end
  end

  def revoke(%Scope{}, _game_id, _expected_version, _opts),
    do: {:error, :invalid_command}

  def regenerate(scope, game_id, expected_version, invite_hours, opts \\ [])

  def regenerate(
        %Scope{user: user},
        game_id,
        expected_version,
        invite_hours,
        opts
      )
      when is_integer(expected_version) and expected_version >= 0 and
             invite_hours in @allowed_invite_hours do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))
    {token, hash} = Keyword.get_lazy(opts, :invite_token, &generate_token/0)

    with {:ok, game_id} <- cast_game_id(game_id) do
      Repo.transact(fn ->
        game = locked_game(game_id)

        with %Game{} <- game,
             :ok <- validate_lobby_admin(game, user.id, expected_version) do
          GameInvite
          |> where([invite], invite.game_id == ^game.id and is_nil(invite.revoked_at))
          |> Repo.update_all(set: [revoked_at: now, updated_at: now])

          invite_result =
            %GameInvite{
              game_id: game.id,
              created_by_user_id: user.id,
              token_hash: hash,
              expires_at: DateTime.add(now, invite_hours, :hour),
              max_uses: game.max_detectives,
              use_count: 0
            }
            |> GameInvite.changeset(%{})
            |> Repo.insert()

          case invite_result do
            {:ok, invite} ->
              updated_game = increment_game_version!(game)

              {:ok,
               %{
                 token: token,
                 invite: invite,
                 version: updated_game.current_version
               }}

            {:error, changeset} ->
              {:error, changeset}
          end
        else
          nil -> {:error, :game_not_found}
          {:error, reason} -> {:error, reason}
        end
      end)
    else
      :error -> {:error, :invalid_game_id}
    end
  end

  def regenerate(%Scope{}, _game_id, _expected_version, _invite_hours, _opts),
    do: {:error, :invalid_invite_expiry}

  def preview(%Scope{user: user}, token, opts \\ []) when is_binary(token) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))

    result =
      GameInvite
      |> join(:inner, [invite], game in assoc(invite, :game))
      |> join(:inner, [_invite, game], host in assoc(game, :host_user))
      |> join(:inner, [_invite, game, _host], version in assoc(game, :case_version))
      |> join(:inner, [_invite, _game, _host, version], case_file in assoc(version, :case_file))
      |> where([invite], invite.token_hash == ^token_hash(token))
      |> select([invite, game, host, _version, case_file], {invite, game, host, case_file})
      |> Repo.one()

    with {invite, game, host, case_file} <- result,
         :ok <- validate_invite(invite, game, now) do
      detective_count = active_detective_count(game.id)

      membership =
        Repo.get_by(GamePlayer, game_id: game.id, user_id: user.id)

      {:ok,
       %{
         game_id: game.id,
         game_title: game.title,
         room_code: game.room_code,
         case_title: case_file.title,
         host_name: host.display_name,
         detective_count: detective_count,
         max_detectives: game.max_detectives,
         places_left: max(game.max_detectives - detective_count, 0),
         expires_at: invite.expires_at,
         membership_status: membership && membership.status
       }}
    else
      nil -> {:error, :invalid_invite}
      {:error, reason} -> {:error, reason}
    end
  end

  def accept(%Scope{user: user}, token, opts \\ []) when is_binary(token) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))
    hash = token_hash(token)

    case Repo.get_by(GameInvite, token_hash: hash) do
      nil ->
        {:error, :invalid_invite}

      unlocked_invite ->
        Repo.transact(fn ->
          game =
            Game
            |> where([game], game.id == ^unlocked_invite.game_id)
            |> lock("FOR UPDATE")
            |> Repo.one()

          invite =
            GameInvite
            |> where([invite], invite.id == ^unlocked_invite.id and invite.token_hash == ^hash)
            |> lock("FOR UPDATE")
            |> Repo.one()

          membership = locked_membership(unlocked_invite.game_id, user.id)

          with %Game{} <- game,
               %GameInvite{} <- invite,
               :ok <- validate_invite(invite, game, now),
               {:ok, membership_action} <- membership_action(membership),
               :ok <- validate_capacity(game) do
            seat = next_detective_seat(game.id, game.max_detectives)

            player =
              persist_membership(
                membership_action,
                membership,
                game.id,
                user.id,
                seat,
                now
              )

            invite
            |> Ecto.Changeset.change(
              use_count: invite.use_count + if(membership_action == :insert, do: 1, else: 0)
            )
            |> Repo.update!()

            {:ok, %{game: game, player: player}}
          else
            nil -> {:error, :invalid_invite}
            {:error, reason} -> {:error, reason}
          end
        end)
    end
  end

  defp validate_invite(invite, game, now) do
    cond do
      game.status != "waiting" -> {:error, :game_not_waiting}
      game.phase != "lobby" -> {:error, :game_not_waiting}
      invite.revoked_at != nil -> {:error, :invite_revoked}
      DateTime.compare(invite.expires_at, now) != :gt -> {:error, :invite_expired}
      invite.use_count >= invite.max_uses -> {:error, :invite_exhausted}
      true -> :ok
    end
  end

  defp membership_action(nil), do: {:ok, :insert}
  defp membership_action(%GamePlayer{status: "left"}), do: {:ok, :reactivate}
  defp membership_action(%GamePlayer{status: "active"}), do: {:error, :already_a_member}
  defp membership_action(%GamePlayer{status: "removed"}), do: {:error, :removed_from_game}

  defp persist_membership(:insert, nil, game_id, user_id, seat, now) do
    %GamePlayer{
      game_id: game_id,
      user_id: user_id,
      role: "detective",
      seat: seat,
      ready: false,
      status: "active",
      joined_at: now
    }
    |> GamePlayer.changeset(%{})
    |> Repo.insert!()
  end

  defp persist_membership(:reactivate, player, _game_id, _user_id, seat, now) do
    player
    |> Ecto.Changeset.change(
      role: "detective",
      seat: seat,
      ready: false,
      status: "active",
      joined_at: now
    )
    |> Repo.update!()
  end

  defp locked_membership(game_id, user_id) do
    GamePlayer
    |> where([player], player.game_id == ^game_id and player.user_id == ^user_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp latest_invite(game_id) do
    GameInvite
    |> where([invite], invite.game_id == ^game_id)
    |> order_by(
      [invite],
      asc_nulls_first: invite.revoked_at,
      desc: invite.inserted_at,
      desc: invite.id
    )
    |> limit(1)
    |> Repo.one()
  end

  defp invite_status(%GameInvite{revoked_at: revoked_at}, _now) when not is_nil(revoked_at),
    do: "revoked"

  defp invite_status(%GameInvite{} = invite, now) do
    cond do
      DateTime.compare(invite.expires_at, now) != :gt -> "expired"
      invite.use_count >= invite.max_uses -> "exhausted"
      true -> "active"
    end
  end

  defp active_invite_exists?(game_id, now) do
    GameInvite
    |> where(
      [invite],
      invite.game_id == ^game_id and is_nil(invite.revoked_at) and
        invite.expires_at > ^now and invite.use_count < invite.max_uses
    )
    |> Repo.exists?()
  end

  defp validate_lobby_admin(game, user_id, expected_version) do
    cond do
      game.status != "waiting" or game.phase != "lobby" -> {:error, :game_not_waiting}
      game.host_user_id != user_id -> {:error, :not_chisel}
      game.current_version != expected_version -> {:error, :stale_version}
      true -> :ok
    end
  end

  defp locked_game(game_id) do
    Game
    |> where([game], game.id == ^game_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp increment_game_version!(game) do
    game
    |> Ecto.Changeset.change(current_version: game.current_version + 1)
    |> Repo.update!()
  end

  defp validate_capacity(game) do
    if active_detective_count(game.id) < game.max_detectives do
      :ok
    else
      {:error, :room_full}
    end
  end

  defp active_detective_count(game_id) do
    GamePlayer
    |> where(
      [player],
      player.game_id == ^game_id and player.role == "detective" and player.status == "active"
    )
    |> Repo.aggregate(:count)
  end

  defp next_detective_seat(game_id, max_detectives) do
    used_seats =
      GamePlayer
      |> where(
        [player],
        player.game_id == ^game_id and player.role == "detective" and player.status == "active"
      )
      |> select([player], player.seat)
      |> Repo.all()
      |> MapSet.new()

    Enum.find(1..max_detectives, &(not MapSet.member?(used_seats, &1)))
  end

  defp cast_game_id(game_id) do
    case Ecto.UUID.cast(game_id) do
      {:ok, cast_id} -> {:ok, cast_id}
      :error -> :error
    end
  end

  defp token_hash(token), do: :crypto.hash(:sha256, token)
end
