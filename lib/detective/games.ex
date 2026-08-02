defmodule Detective.Games do
  @moduledoc """
  Room lifecycle and membership operations.
  """

  import Ecto.Query, warn: false

  alias Detective.Accounts.Scope
  alias Detective.Cases
  alias Detective.Games.{Game, GamePlayer}
  alias Detective.Invitations
  alias Detective.Invitations.GameInvite
  alias Detective.Repo
  alias Ecto.Multi

  @default_invite_hours 24

  def create_game(%Scope{user: user}, attrs, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))
    room_code = Keyword.get_lazy(opts, :room_code, &generate_room_code/0)
    invite_hours = parse_invite_hours(attrs)
    case_version_id = value(attrs, :case_version_id)

    with %{} <- Cases.get_published_version(case_version_id),
         true <- invite_hours in [1, 6, 24, 72] do
      {invite_token, token_hash} =
        Keyword.get_lazy(opts, :invite_token, &Invitations.generate_token/0)

      game_attrs = %{
        "title" => value(attrs, :title),
        "case_version_id" => case_version_id,
        "max_detectives" => value(attrs, :max_detectives)
      }

      multi =
        Multi.new()
        |> Multi.insert(
          :game,
          Game.create_changeset(
            %Game{
              room_code: room_code,
              host_user_id: user.id,
              status: "waiting",
              phase: "lobby",
              current_version: 0
            },
            game_attrs
          )
        )
        |> Multi.insert(:chisel, fn %{game: game} ->
          GamePlayer.changeset(
            %GamePlayer{
              game_id: game.id,
              user_id: user.id,
              role: "chisel",
              ready: true,
              status: "active",
              joined_at: now
            },
            %{}
          )
        end)
        |> Multi.insert(:invite, fn %{game: game} ->
          GameInvite.changeset(
            %GameInvite{
              game_id: game.id,
              created_by_user_id: user.id,
              token_hash: token_hash,
              expires_at: DateTime.add(now, invite_hours, :hour),
              max_uses: game.max_detectives,
              use_count: 0
            },
            %{}
          )
        end)

      case Repo.transact(multi) do
        {:ok, %{game: game, invite: invite}} ->
          {:ok, %{game: game, invite: invite, invite_token: invite_token}}

        {:error, _operation, changeset, _changes} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :case_version_not_published}
      false -> {:error, :invalid_invite_expiry}
    end
  end

  def change_game(%Scope{user: user}, attrs \\ %{}) do
    game_attrs = %{
      "title" => value(attrs, :title),
      "case_version_id" => value(attrs, :case_version_id),
      "max_detectives" => value(attrs, :max_detectives)
    }

    Game.create_changeset(
      %Game{
        room_code: "ABC234",
        host_user_id: user.id,
        status: "waiting",
        phase: "lobby",
        current_version: 0
      },
      game_attrs
    )
  end

  def game_summary(%Scope{user: user}) do
    Game
    |> join(:inner, [game], player in GamePlayer,
      on: player.game_id == game.id and player.user_id == ^user.id and player.status == "active"
    )
    |> group_by([game], game.status)
    |> select([game], {game.status, count(game.id)})
    |> Repo.all()
    |> Map.new()
    |> then(fn counts ->
      %{
        waiting: Map.get(counts, "waiting", 0),
        active: Map.get(counts, "active", 0),
        finished: Map.get(counts, "finished", 0)
      }
    end)
  end

  def get_lobby(%Scope{user: user}, game_id) do
    with {:ok, game_id} <- cast_game_id(game_id),
         %{id: _id} = membership <- membership_projection(game_id, user.id),
         {:ok, lobby} <- public_lobby(game_id) do
      {:ok, Map.put(lobby, :membership, membership)}
    else
      :error -> {:error, :invalid_game_id}
      nil -> {:error, :not_a_member}
      {:error, reason} -> {:error, reason}
    end
  end

  def public_lobby(game_id) do
    with {:ok, game_id} <- cast_game_id(game_id),
         %{id: _id} = game <- lobby_game_projection(game_id) do
      {:ok, Map.put(game, :players, lobby_player_projections(game_id))}
    else
      :error -> {:error, :invalid_game_id}
      nil -> {:error, :game_not_found}
    end
  end

  def set_ready(%Scope{user: user} = scope, game_id, expected_version, ready)
      when is_integer(expected_version) and is_boolean(ready) do
    with {:ok, game_id} <- cast_game_id(game_id),
         {:ok, result} <- transact_ready(user.id, game_id, expected_version, ready),
         {:ok, lobby} <- get_lobby(scope, game_id) do
      event = if ready, do: :player_ready, else: :player_unready
      {:ok, %{event: event, player_id: result.player_id, lobby: lobby}}
    else
      :error -> {:error, :invalid_game_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def set_ready(%Scope{}, _game_id, _expected_version, _ready),
    do: {:error, :invalid_command}

  defp parse_invite_hours(attrs) do
    case value(attrs, :invite_hours) do
      hours when is_integer(hours) -> hours
      hours when is_binary(hours) -> parse_integer(hours)
      _ -> @default_invite_hours
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp transact_ready(user_id, game_id, expected_version, ready) do
    Repo.transact(fn ->
      game =
        Game
        |> where([game], game.id == ^game_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      player =
        GamePlayer
        |> where(
          [player],
          player.game_id == ^game_id and player.user_id == ^user_id and
            player.status == "active"
        )
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %Game{} <- game,
           %GamePlayer{} <- player,
           :ok <- validate_waiting_lobby(game),
           :ok <- validate_detective(player),
           :ok <- validate_version(game, expected_version) do
        player
        |> GamePlayer.ready_changeset(ready)
        |> Repo.update!()

        game
        |> Ecto.Changeset.change(current_version: game.current_version + 1)
        |> Repo.update!()

        {:ok, %{player_id: player.id}}
      else
        nil -> {:error, :not_a_member}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp membership_projection(game_id, user_id) do
    GamePlayer
    |> where(
      [player],
      player.game_id == ^game_id and player.user_id == ^user_id and player.status == "active"
    )
    |> select([player], %{
      id: player.id,
      role: player.role,
      ready: player.ready,
      seat: player.seat
    })
    |> Repo.one()
  end

  defp lobby_game_projection(game_id) do
    Game
    |> join(:inner, [game], version in assoc(game, :case_version))
    |> join(:inner, [_game, version], case_file in assoc(version, :case_file))
    |> where([game], game.id == ^game_id)
    |> select([game, version, case_file], %{
      id: game.id,
      title: game.title,
      room_code: game.room_code,
      status: game.status,
      phase: game.phase,
      max_detectives: game.max_detectives,
      current_version: game.current_version,
      case_title: case_file.title,
      case_version: version.version
    })
    |> Repo.one()
  end

  defp lobby_player_projections(game_id) do
    GamePlayer
    |> join(:inner, [player], user in assoc(player, :user))
    |> where([player], player.game_id == ^game_id and player.status == "active")
    |> order_by([player], asc: player.role, asc: player.seat)
    |> select([player, user], %{
      id: player.id,
      display_name: user.display_name,
      role: player.role,
      ready: player.ready,
      seat: player.seat
    })
    |> Repo.all()
  end

  defp validate_waiting_lobby(%Game{status: "waiting", phase: "lobby"}), do: :ok
  defp validate_waiting_lobby(%Game{}), do: {:error, :game_not_waiting}

  defp validate_detective(%GamePlayer{role: "detective"}), do: :ok
  defp validate_detective(%GamePlayer{}), do: {:error, :not_detective}

  defp validate_version(%Game{current_version: version}, version), do: :ok
  defp validate_version(%Game{}, _expected_version), do: {:error, :stale_version}

  defp cast_game_id(game_id) do
    case Ecto.UUID.cast(game_id) do
      {:ok, cast_id} -> {:ok, cast_id}
      :error -> :error
    end
  end

  defp generate_room_code do
    :crypto.strong_rand_bytes(5)
    |> Base.encode32(case: :upper, padding: false)
    |> binary_part(0, 6)
  end
end
