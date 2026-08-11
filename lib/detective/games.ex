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
    GameEvent,
    GamePlayer,
    LobbyBroadcaster,
    Persistence,
    PlayerNote,
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
  @replay_page_size 30

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
              rematch_of_game_id: Keyword.get(opts, :rematch_of_game_id),
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

  def rematch(scope, game_id, opts \\ [])

  def rematch(%Scope{user: %{id: user_id}} = scope, game_id, opts) do
    with {:ok, game_id} <- cast_game_id(game_id),
         %Game{} = source <- Repo.get(Game, game_id),
         :ok <- validate_rematch_source(source, user_id) do
      case rematch_game(source.id, user_id) do
        %Game{} = game ->
          {:ok, %{game: game, invite_token: nil, duplicate: true}}

        nil ->
          attrs = %{
            title: rematch_title(source.title),
            case_version_id: source.case_version_id,
            max_detectives: source.max_detectives,
            invite_hours: 24
          }

          opts = Keyword.put(opts, :rematch_of_game_id, source.id)

          case create_game(scope, attrs, opts) do
            {:ok, result} ->
              {:ok, Map.put(result, :duplicate, false)}

            {:error, %Ecto.Changeset{} = changeset} ->
              recover_rematch(changeset, source.id, user_id)

            {:error, reason} ->
              {:error, reason}
          end
      end
    else
      :error -> {:error, :invalid_game_id}
      nil -> {:error, :not_rematchable}
      {:error, reason} -> {:error, reason}
    end
  end

  def rematch(%Scope{}, _game_id, _opts), do: {:error, :not_rematchable}

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
        won:
          game.winner_user_id == ^user.id or
            (game.finish_reason == "chisel_forfeit" and player.role == "detective"),
        winner_role: game.winner_role,
        finish_reason: game.finish_reason,
        case_title: case_file.title,
        detective_count: fragment("COALESCE(?, 0)", counts.count),
        max_detectives: game.max_detectives,
        started_at: game.started_at,
        finished_at: game.finished_at,
        updated_at: game.updated_at
      })
      |> Repo.all()

    Enum.reduce(rows, %{waiting: [], active: [], finished: []}, fn row, acc ->
      bucket = dashboard_bucket(row.status)
      Map.update!(acc, bucket, &(&1 ++ [row]))
    end)
  end

  def replay_page(%Scope{user: %{id: user_id}}, game_id, page)
      when is_integer(page) and page >= 0 do
    with {:ok, game_id} <- cast_game_id(game_id),
         %{id: _id} = header <- replay_header(game_id, user_id),
         event_count <- replay_event_count(game_id),
         true <- replay_page_available?(page, event_count) do
      events = replay_events(game_id, page)

      {:ok,
       header
       |> Map.put(:events, Enum.take(events, @replay_page_size))
       |> Map.put(:page, page)
       |> Map.put(:has_previous, page > 0)
       |> Map.put(:has_next, length(events) > @replay_page_size)
       |> Map.put(:players, replay_players(game_id))
       |> Map.put(:reference, replay_reference(game_id))}
    else
      :error -> {:error, :invalid_game_id}
      nil -> {:error, :replay_unavailable}
      false -> {:error, :replay_unavailable}
    end
  end

  def replay_page(%Scope{}, _game_id, _page), do: {:error, :replay_unavailable}

  def get_player_note(%Scope{user: %{id: user_id}}, game_id) do
    with {:ok, game_id} <- cast_game_id(game_id),
         %{status: status} when status in ["active", "paused", "finished"] <-
           note_membership(game_id, user_id) do
      case Repo.get_by(PlayerNote, game_id: game_id, user_id: user_id) do
        %PlayerNote{} = note -> {:ok, note}
        nil -> {:ok, %PlayerNote{game_id: game_id, user_id: user_id, content: ""}}
      end
    else
      :error -> {:error, :invalid_game_id}
      nil -> {:error, :not_a_member}
      %{status: _status} -> {:error, :notes_unavailable}
    end
  end

  def get_player_note(%Scope{}, _game_id), do: {:error, :not_a_member}

  def save_player_note(%Scope{user: %{id: user_id}} = scope, game_id, content)
      when is_binary(content) do
    with {:ok, %PlayerNote{} = note} <- get_player_note(scope, game_id) do
      if String.trim(content) == "" do
        PlayerNote
        |> where(
          [player_note],
          player_note.game_id == ^note.game_id and player_note.user_id == ^user_id
        )
        |> Repo.delete_all()

        {:ok, %{note | id: nil, content: ""}}
      else
        %PlayerNote{game_id: note.game_id, user_id: user_id}
        |> PlayerNote.changeset(%{content: content})
        |> Repo.insert(
          on_conflict: [set: [content: content, updated_at: DateTime.utc_now(:second)]],
          conflict_target: [:game_id, :user_id],
          returning: true
        )
      end
    end
  end

  def save_player_note(%Scope{}, _game_id, _content), do: {:error, :invalid_note}

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

  def cancel_lobby(scope, game_id, expected_version, opts \\ [])

  def cancel_lobby(%Scope{user: %{id: user_id}}, game_id, expected_version, opts)
      when is_integer(expected_version) and expected_version >= 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))

    with {:ok, game_id} <- cast_game_id(game_id) do
      Repo.transact(fn ->
        game =
          Game
          |> where([game], game.id == ^game_id)
          |> lock("FOR UPDATE")
          |> Repo.one()

        with %Game{} <- game,
             :ok <- validate_waiting_lobby(game),
             :ok <- validate_host(game, user_id),
             :ok <- validate_version(game, expected_version) do
          GameInvite
          |> where([invite], invite.game_id == ^game.id and is_nil(invite.revoked_at))
          |> Repo.update_all(set: [revoked_at: now, updated_at: now])

          updated_game =
            game
            |> Game.transition_changeset(%{
              status: "cancelled",
              phase: "lobby",
              current_version: game.current_version + 1,
              finished_at: now,
              finish_reason: "host_cancelled"
            })
            |> Repo.update!()

          {:ok, %{game_id: updated_game.id, version: updated_game.current_version}}
        else
          nil -> {:error, :game_not_found}
          {:error, reason} -> {:error, reason}
        end
      end)
    else
      :error -> {:error, :invalid_game_id}
    end
  end

  def cancel_lobby(%Scope{}, _game_id, _expected_version, _opts),
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

  defp replay_header(game_id, user_id) do
    GamePlayer
    |> join(:inner, [player], game in assoc(player, :game))
    |> join(:inner, [_player, game], version in assoc(game, :case_version))
    |> join(:inner, [_player, _game, version], case_file in assoc(version, :case_file))
    |> where(
      [player, game],
      player.game_id == ^game_id and player.user_id == ^user_id and
        player.status == "active" and game.status == "finished"
    )
    |> select([player, game, _version, case_file], %{
      id: game.id,
      title: game.title,
      case_title: case_file.title,
      room_code: game.room_code,
      role: player.role,
      winner_role: game.winner_role,
      won:
        game.winner_user_id == ^user_id or
          (game.finish_reason == "chisel_forfeit" and player.role == "detective"),
      finish_reason: game.finish_reason,
      started_at: game.started_at,
      finished_at: game.finished_at
    })
    |> Repo.one()
  end

  defp replay_events(game_id, page) do
    GameEvent
    |> where([event], event.game_id == ^game_id)
    |> order_by([event], asc: event.sequence)
    |> offset(^(page * @replay_page_size))
    |> limit(^(@replay_page_size + 1))
    |> select([event], %{
      id: event.id,
      sequence: event.sequence,
      event_type: event.event_type,
      public_payload: event.public_payload,
      inserted_at: event.inserted_at
    })
    |> Repo.all()
  end

  defp replay_event_count(game_id) do
    GameEvent
    |> where([event], event.game_id == ^game_id)
    |> Repo.aggregate(:count)
  end

  defp replay_page_available?(0, _event_count), do: true

  defp replay_page_available?(page, event_count) when event_count > 0,
    do: page <= div(event_count - 1, @replay_page_size)

  defp replay_page_available?(_page, _event_count), do: false

  defp replay_players(game_id) do
    GamePlayer
    |> join(:inner, [player], user in assoc(player, :user))
    |> where([player], player.game_id == ^game_id and player.status == "active")
    |> select([player, user], {player.id, user.display_name})
    |> Repo.all()
    |> Map.new()
  end

  defp replay_reference(game_id) do
    case Persistence.load_state(game_id) do
      {:ok, %State{} = state} ->
        %{
          locations: Map.new(state.locations, fn {id, location} -> {id, location.name} end),
          suspects: Map.new(state.suspects, fn {id, suspect} -> {id, suspect.name} end),
          special_actors: Map.new(state.special_actors, fn {id, actor} -> {id, actor.name} end)
        }

      {:error, _reason} ->
        %{locations: %{}, suspects: %{}, special_actors: %{}}
    end
  end

  defp note_membership(game_id, user_id) do
    GamePlayer
    |> join(:inner, [player], game in assoc(player, :game))
    |> where(
      [player],
      player.game_id == ^game_id and player.user_id == ^user_id and player.status == "active"
    )
    |> select([_player, game], %{status: game.status})
    |> Repo.one()
  end

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
    |> where([game], game.id == ^game_id and game.status in ["waiting", "active"])
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

  defp validate_playable_state(%State{status: status})
       when status in [:active, :paused, :finished],
       do: :ok

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

  defp validate_rematch_source(%Game{status: "finished", host_user_id: user_id}, user_id),
    do: :ok

  defp validate_rematch_source(%Game{}, _user_id), do: {:error, :not_rematchable}

  defp recover_rematch(changeset, source_game_id, user_id) do
    if Keyword.has_key?(changeset.errors, :rematch_of_game_id) do
      case rematch_game(source_game_id, user_id) do
        %Game{} = game -> {:ok, %{game: game, invite_token: nil, duplicate: true}}
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp rematch_game(source_game_id, user_id) do
    Game
    |> where(
      [game],
      game.rematch_of_game_id == ^source_game_id and game.host_user_id == ^user_id
    )
    |> Repo.one()
  end

  defp rematch_title(title) do
    suffix = " — Rematch"
    max_prefix_length = 80 - String.length(suffix)
    String.slice(title, 0, max_prefix_length) <> suffix
  end
end
