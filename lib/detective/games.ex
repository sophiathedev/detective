defmodule Detective.Games do
  @moduledoc """
  Room lifecycle and membership operations.
  """

  import Ecto.Query, warn: false

  alias Detective.Accounts.Scope
  alias Detective.Cases
  alias Detective.Cases.CaseVersion

  alias Detective.Games.{
    Engine,
    Game,
    GamePlayer,
    LobbyBroadcaster,
    Persistence,
    Projections,
    Session,
    SessionSupervisor,
    State
  }

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
        active: Map.get(counts, "active", 0) + Map.get(counts, "paused", 0),
        finished: Map.get(counts, "finished", 0)
      }
    end)
  end

  def list_game_dossiers(%Scope{user: user}) do
    detective_counts =
      GamePlayer
      |> where([player], player.status == "active" and player.role == "detective")
      |> group_by([player], player.game_id)
      |> select([player], %{game_id: player.game_id, count: count(player.id)})

    rows =
      GamePlayer
      |> join(:inner, [player], game in assoc(player, :game))
      |> join(:inner, [_player, game], version in assoc(game, :case_version))
      |> join(:inner, [_player, _game, version], case_file in assoc(version, :case_file))
      |> join(:left, [_player, game], counts in subquery(detective_counts),
        on: counts.game_id == game.id
      )
      |> where(
        [player, game],
        player.user_id == ^user.id and player.status == "active" and
          game.status in ["waiting", "active", "paused", "finished"]
      )
      |> order_by([_player, game], desc: game.updated_at)
      |> select([player, game, _version, case_file, counts], %{
        id: game.id,
        title: game.title,
        room_code: game.room_code,
        status: game.status,
        phase: game.phase,
        role: player.role,
        case_title: case_file.title,
        detective_count: fragment("COALESCE(?, 0)", counts.count),
        max_detectives: game.max_detectives,
        updated_at: game.updated_at
      })
      |> Repo.all()

    Enum.reduce(rows, %{waiting: [], active: [], finished: []}, fn row, acc ->
      bucket = dashboard_bucket(row.status)
      Map.update!(acc, bucket, &(&1 ++ [row]))
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
      {:ok,
       game
       |> Map.put(:players, lobby_player_projections(game_id))
       |> Map.put(:invite, Invitations.lobby_status(game_id))}
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

  def leave_lobby(%Scope{user: user}, game_id, expected_version)
      when is_integer(expected_version) and expected_version >= 0 do
    with {:ok, game_id} <- cast_game_id(game_id),
         {:ok, result} <- transact_leave_lobby(user.id, game_id, expected_version),
         {:ok, lobby} <- public_lobby(game_id) do
      {:ok, %{event: :player_left, player_id: result.player_id, lobby: lobby}}
    else
      :error -> {:error, :invalid_game_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def leave_lobby(%Scope{}, _game_id, _expected_version),
    do: {:error, :invalid_command}

  def remove_player(%Scope{user: user}, game_id, player_id, expected_version)
      when is_integer(expected_version) and expected_version >= 0 do
    with {:ok, game_id} <- cast_game_id(game_id),
         {:ok, player_id} <- cast_player_id(player_id),
         {:ok, result} <-
           transact_remove_player(user.id, game_id, player_id, expected_version),
         {:ok, lobby} <- get_lobby(Scope.for_user(user), game_id) do
      {:ok, %{event: :player_removed, player_id: result.player_id, lobby: lobby}}
    else
      :error -> {:error, :invalid_command}
      {:error, reason} -> {:error, reason}
    end
  end

  def remove_player(%Scope{}, _game_id, _player_id, _expected_version),
    do: {:error, :invalid_command}

  def update_lobby_settings(
        %Scope{user: user} = scope,
        game_id,
        attrs,
        expected_version
      )
      when is_map(attrs) and is_integer(expected_version) and expected_version >= 0 do
    max_detectives = parse_lobby_capacity(value(attrs, :max_detectives))

    with {:ok, game_id} <- cast_game_id(game_id),
         {:ok, case_version_id} <- cast_case_version_id(value(attrs, :case_version_id)),
         true <- max_detectives in 2..4,
         %CaseVersion{} <- Cases.get_published_version(case_version_id),
         {:ok, _result} <-
           transact_lobby_settings(
             user.id,
             game_id,
             case_version_id,
             max_detectives,
             expected_version
           ),
         {:ok, lobby} <- get_lobby(scope, game_id) do
      {:ok, %{event: :lobby_settings_updated, lobby: lobby}}
    else
      :error -> {:error, :invalid_lobby_settings}
      false -> {:error, :invalid_lobby_settings}
      nil -> {:error, :case_version_not_published}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_lobby_settings(%Scope{}, _game_id, _attrs, _expected_version),
    do: {:error, :invalid_command}

  def start_game(scope, game_id, command_id, expected_version, opts \\ [])

  def start_game(
        %Scope{user: user} = scope,
        game_id,
        command_id,
        expected_version,
        opts
      )
      when is_integer(expected_version) and expected_version >= 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))

    with {:ok, game_id} <- cast_game_id(game_id),
         {:ok, command_id} <- cast_command_id(command_id),
         :new <- start_command_status(game_id, user.id, command_id, expected_version),
         {:ok, _changes} <-
           Repo.transact(start_game_multi(user.id, game_id, command_id, expected_version, now)),
         {:ok, _pid} <- SessionSupervisor.ensure_session(game_id),
         {:ok, lobby} <- get_lobby(scope, game_id) do
      :ok = LobbyBroadcaster.broadcast_game_started(lobby)
      {:ok, %{event: :game_started, duplicate: false, lobby: lobby}}
    else
      :duplicate ->
        with {:ok, lobby} <- get_lobby(scope, game_id) do
          {:ok, %{event: :game_started, duplicate: true, lobby: lobby}}
        end

      :conflict ->
        {:error, :command_id_conflict}

      :error ->
        {:error, :invalid_command}

      {:error, operation, reason, _changes}
      when operation in [:locked_game, :players, :case_version, :initial_state] ->
        {:error, reason}

      {:error, :start_command, _changeset, _changes} ->
        {:error, :duplicate_command}

      {:error, _operation, reason, _changes} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_game(%Scope{}, _game_id, _command_id, _expected_version, _opts),
    do: {:error, :invalid_command}

  def game_projection(%Scope{user: user}, game_id) do
    with {:ok, game_id} <- cast_game_id(game_id),
         %{id: _id} <- membership_projection(game_id, user.id),
         {:ok, state} <- Session.get_state(game_id),
         :ok <- validate_playable_state(state),
         {:ok, projection} <- Projections.for_user(state, user.id) do
      {:ok, projection}
    else
      :error -> {:error, :invalid_game_id}
      nil -> {:error, :not_a_member}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_invite_hours(attrs) do
    case value(attrs, :invite_hours) do
      hours when is_integer(hours) -> hours
      hours when is_binary(hours) -> parse_integer(hours)
      _ -> @default_invite_hours
    end
  end

  defp dashboard_bucket("waiting"), do: :waiting
  defp dashboard_bucket(status) when status in ["active", "paused"], do: :active
  defp dashboard_bucket("finished"), do: :finished

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_lobby_capacity(value) when is_integer(value), do: value
  defp parse_lobby_capacity(value) when is_binary(value), do: parse_integer(value)
  defp parse_lobby_capacity(_value), do: nil

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

  defp transact_leave_lobby(user_id, game_id, expected_version) do
    Repo.transact(fn ->
      game = locked_game(game_id)
      player = locked_active_player(game_id, user_id)

      with %Game{} <- game,
           %GamePlayer{} <- player,
           :ok <- validate_waiting_lobby(game),
           :ok <- validate_detective(player),
           :ok <- validate_version(game, expected_version) do
        player
        |> Ecto.Changeset.change(status: "left", ready: false)
        |> Repo.update!()

        increment_lobby_version!(game)

        {:ok, %{player_id: player.id}}
      else
        nil -> {:error, if(game, do: :not_a_member, else: :game_not_found)}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp transact_remove_player(actor_id, game_id, player_id, expected_version) do
    Repo.transact(fn ->
      game = locked_game(game_id)

      player =
        GamePlayer
        |> where(
          [player],
          player.game_id == ^game_id and player.id == ^player_id and player.status == "active"
        )
        |> lock("FOR UPDATE")
        |> Repo.one()

      with %Game{} <- game,
           :ok <- validate_waiting_lobby(game),
           :ok <- validate_host(game, actor_id),
           :ok <- validate_version(game, expected_version),
           %GamePlayer{} <- player,
           :ok <- validate_detective(player) do
        player
        |> Ecto.Changeset.change(status: "removed", ready: false)
        |> Repo.update!()

        increment_lobby_version!(game)

        {:ok, %{player_id: player.id}}
      else
        nil -> {:error, if(game, do: :player_not_found, else: :game_not_found)}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp transact_lobby_settings(
         actor_id,
         game_id,
         case_version_id,
         max_detectives,
         expected_version
       ) do
    Repo.transact(fn ->
      game = locked_game(game_id)

      detective_count =
        GamePlayer
        |> where(
          [player],
          player.game_id == ^game_id and player.role == "detective" and
            player.status == "active"
        )
        |> Repo.aggregate(:count)

      with %Game{} <- game,
           :ok <- validate_waiting_lobby(game),
           :ok <- validate_host(game, actor_id),
           :ok <- validate_version(game, expected_version),
           :ok <- validate_lobby_capacity(max_detectives, detective_count) do
        update_result =
          game
          |> Game.create_changeset(%{
            "title" => game.title,
            "case_version_id" => case_version_id,
            "max_detectives" => max_detectives
          })
          |> Ecto.Changeset.change(current_version: game.current_version + 1)
          |> Repo.update()

        case update_result do
          {:ok, updated_game} ->
            now = DateTime.utc_now(:second)

            GameInvite
            |> where([invite], invite.game_id == ^game.id and is_nil(invite.revoked_at))
            |> Repo.all()
            |> Enum.each(fn invite ->
              invite
              |> Ecto.Changeset.change(
                max_uses: max(max_detectives, invite.use_count),
                updated_at: now
              )
              |> Repo.update!()
            end)

            {:ok, %{version: updated_game.current_version}}

          {:error, changeset} ->
            {:error, changeset}
        end
      else
        nil -> {:error, :game_not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp locked_game(game_id) do
    Game
    |> where([game], game.id == ^game_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_active_player(game_id, user_id) do
    GamePlayer
    |> where(
      [player],
      player.game_id == ^game_id and player.user_id == ^user_id and
        player.status == "active"
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp increment_lobby_version!(game) do
    game
    |> Ecto.Changeset.change(current_version: game.current_version + 1)
    |> Repo.update!()
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
      case_version_id: version.id,
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

  defp validate_host(%Game{host_user_id: user_id}, user_id), do: :ok
  defp validate_host(%Game{}, _user_id), do: {:error, :not_chisel}

  defp validate_lobby_capacity(max_detectives, detective_count)
       when max_detectives >= detective_count,
       do: :ok

  defp validate_lobby_capacity(_max_detectives, _detective_count),
    do: {:error, :capacity_below_membership}

  defp validate_version(%Game{current_version: version}, version), do: :ok
  defp validate_version(%Game{}, _expected_version), do: {:error, :stale_version}

  defp validate_playable_state(%State{status: status}) when status in [:active, :paused], do: :ok
  defp validate_playable_state(%State{}), do: {:error, :game_not_active}

  defp cast_game_id(game_id) do
    case Ecto.UUID.cast(game_id) do
      {:ok, cast_id} -> {:ok, cast_id}
      :error -> :error
    end
  end

  defp cast_player_id(player_id) do
    case Ecto.UUID.cast(player_id) do
      {:ok, cast_id} -> {:ok, cast_id}
      :error -> :error
    end
  end

  defp cast_case_version_id(case_version_id) do
    case Ecto.UUID.cast(case_version_id) do
      {:ok, cast_id} -> {:ok, cast_id}
      :error -> :error
    end
  end

  defp cast_command_id(command_id) do
    case Ecto.UUID.cast(command_id) do
      {:ok, cast_id} -> {:ok, cast_id}
      :error -> :error
    end
  end

  defp start_command_status(game_id, actor_id, command_id, expected_version) do
    case Persistence.lookup_command(game_id, command_id) do
      nil ->
        :new

      record ->
        if record.actor_id == actor_id and record.command_type == "start_game" and
             record.expected_version == expected_version and
             record.payload_digest == Persistence.payload_digest(%{}) do
          :duplicate
        else
          :conflict
        end
    end
  end

  defp start_game_multi(actor_id, game_id, command_id, expected_version, now) do
    Multi.new()
    |> Multi.run(:locked_game, fn repo, _changes ->
      game =
        Game
        |> where([game], game.id == ^game_id)
        |> lock("FOR UPDATE")
        |> repo.one()

      cond do
        game == nil -> {:error, :game_not_found}
        game.status != "waiting" or game.phase != "lobby" -> {:error, :game_not_waiting}
        game.current_version != expected_version -> {:error, :stale_version}
        game.host_user_id != actor_id -> {:error, :not_chisel}
        true -> {:ok, game}
      end
    end)
    |> Multi.run(:players, fn repo, %{locked_game: game} ->
      players =
        GamePlayer
        |> where([player], player.game_id == ^game.id and player.status == "active")
        |> order_by([player], asc: player.role, asc: player.seat)
        |> lock("FOR UPDATE")
        |> preload(:user)
        |> repo.all()

      detectives = Enum.filter(players, &(&1.role == "detective"))
      chisels = Enum.filter(players, &(&1.role == "chisel"))

      cond do
        length(chisels) != 1 -> {:error, :invalid_chisel_count}
        length(detectives) < 2 -> {:error, :not_enough_detectives}
        length(detectives) > 4 -> {:error, :too_many_detectives}
        Enum.any?(detectives, &(not &1.ready)) -> {:error, :detectives_not_ready}
        true -> {:ok, players}
      end
    end)
    |> Multi.run(:case_version, fn repo, %{locked_game: game} ->
      case repo.get(CaseVersion, game.case_version_id) do
        %CaseVersion{published_at: published_at} = version when not is_nil(published_at) ->
          {:ok, version}

        _version ->
          {:error, :case_version_not_published}
      end
    end)
    |> Multi.run(:initial_state, fn _repo,
                                    %{
                                      locked_game: game,
                                      players: players,
                                      case_version: case_version
                                    } ->
      engine_players =
        Enum.map(players, fn player ->
          %{
            id: player.id,
            user_id: player.user_id,
            display_name: player.user.display_name,
            role: player.role,
            seat: player.seat
          }
        end)

      case Engine.new(game, engine_players, case_version.content) do
        {:ok, state} ->
          {:ok, %{state | version: game.current_version + 1}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
    |> Multi.update(:started_game, fn %{locked_game: game, initial_state: state} ->
      Game.transition_changeset(game, %{
        status: "active",
        phase: "detective_turn",
        current_version: state.version,
        started_at: now
      })
    end)
    |> Multi.merge(fn %{initial_state: state} ->
      Persistence.initial_records_multi(
        Multi.new(),
        game_id,
        actor_id,
        command_id,
        expected_version,
        state
      )
    end)
  end

  defp generate_room_code do
    :crypto.strong_rand_bytes(5)
    |> Base.encode32(case: :upper, padding: false)
    |> binary_part(0, 6)
  end
end
