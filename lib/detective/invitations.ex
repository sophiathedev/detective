defmodule Detective.Invitations do
  @moduledoc """
  Hashed room invitations and capacity-safe acceptance.
  """

  import Ecto.Query, warn: false

  alias Detective.Accounts.Scope
  alias Detective.Games.{Game, GamePlayer}
  alias Detective.Invitations.GameInvite
  alias Detective.Repo

  def generate_token do
    token =
      :crypto.strong_rand_bytes(32)
      |> Base.url_encode64(padding: false)

    {token, token_hash(token)}
  end

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

          with %Game{} <- game,
               %GameInvite{} <- invite,
               :ok <- validate_invite(invite, game, now),
               :ok <- validate_membership(game.id, user.id),
               :ok <- validate_capacity(game) do
            player =
              %GamePlayer{
                game_id: game.id,
                user_id: user.id,
                role: "detective",
                seat: next_detective_seat(game.id),
                ready: false,
                status: "active",
                joined_at: now
              }
              |> GamePlayer.changeset(%{})
              |> Repo.insert!()

            invite
            |> Ecto.Changeset.change(use_count: invite.use_count + 1)
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

  defp validate_membership(game_id, user_id) do
    case Repo.get_by(GamePlayer, game_id: game_id, user_id: user_id) do
      nil -> :ok
      %GamePlayer{status: "active"} -> {:error, :already_a_member}
      %GamePlayer{status: "removed"} -> {:error, :removed_from_game}
      %GamePlayer{} -> {:error, :membership_exists}
    end
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

  defp next_detective_seat(game_id) do
    GamePlayer
    |> where(
      [player],
      player.game_id == ^game_id and player.role == "detective" and player.status == "active"
    )
    |> select([player], coalesce(max(player.seat), 0))
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp token_hash(token), do: :crypto.hash(:sha256, token)
end
