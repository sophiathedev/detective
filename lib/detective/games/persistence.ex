defmodule Detective.Games.Persistence do
  @moduledoc """
  Transactional command, event, and snapshot persistence.
  """

  import Ecto.Query, warn: false

  alias Detective.Games.{
    Command,
    CommandRecord,
    Event,
    Game,
    GameEvent,
    GamePrivateEvent,
    GameSnapshot,
    SnapshotCodec,
    State
  }

  alias Detective.Repo
  alias Ecto.Multi

  @persisted_event_types %{
    "detective_placed" => :detective_placed,
    "player_moved" => :player_moved,
    "evidence_analyzed" => :evidence_analyzed,
    "kickback_collected" => :kickback_collected,
    "location_searched" => :location_searched,
    "suspect_searched" => :suspect_searched,
    "evidence_submitted" => :evidence_submitted,
    "free_question_declined" => :free_question_declined,
    "question_allowed" => :question_allowed,
    "question_blocked" => :question_blocked,
    "question_abandoned" => :question_abandoned,
    "goon_bribed" => :goon_bribed,
    "snitch_decision_recorded" => :snitch_decision_recorded,
    "snitch_window_closed" => :snitch_window_closed,
    "snitches_resolved" => :snitches_resolved,
    "interrogation_started" => :interrogation_started,
    "response_published" => :response_published,
    "response_accepted" => :response_accepted,
    "challenge_succeeded" => :challenge_succeeded,
    "challenge_failed" => :challenge_failed,
    "accusation_submitted" => :accusation_submitted,
    "accusation_rejected" => :accusation_rejected,
    "final_guess_submitted" => :final_guess_submitted,
    "game_finished" => :game_finished,
    "turn_ended" => :turn_ended,
    "turn_started" => :turn_started,
    "day_advanced" => :day_advanced,
    "accusation_opened" => :accusation_opened
  }

  def load_state(game_id) do
    snapshot =
      GameSnapshot
      |> where([snapshot], snapshot.game_id == ^game_id)
      |> order_by([snapshot], desc: snapshot.version)
      |> limit(1)
      |> Repo.one()

    case snapshot do
      %GameSnapshot{} -> SnapshotCodec.load(snapshot.state_json)
      nil -> {:error, :snapshot_not_found}
    end
  end

  def lookup_command(game_id, command_id) do
    Repo.get_by(CommandRecord, game_id: game_id, command_id: command_id)
  end

  def command_matches?(%CommandRecord{} = record, actor_id, %Command{} = command) do
    record.actor_id == actor_id and record.command_type == Atom.to_string(command.type) and
      record.payload_digest == payload_digest(command.payload)
  end

  def events_for_command(game_id, command_id, version) do
    events =
      GameEvent
      |> where([event], event.game_id == ^game_id and event.command_id == ^command_id)
      |> order_by([event], asc: event.sequence)
      |> Repo.all()

    event_ids = Enum.map(events, & &1.id)

    private_payloads =
      GamePrivateEvent
      |> where([event], event.game_event_id in ^event_ids)
      |> Repo.all()
      |> Enum.group_by(& &1.game_event_id)

    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      case Map.fetch(@persisted_event_types, event.event_type) do
        {:ok, type} ->
          recipients =
            private_payloads
            |> Map.get(event.id, [])
            |> Map.new(&{&1.recipient_user_id, &1.payload})

          restored = %Event{
            type: type,
            public_payload: event.public_payload,
            private_payloads: recipients,
            delivery_id: event.id,
            version: version
          }

          {:cont, {:ok, [restored | acc]}}

        :error ->
          {:halt, {:error, :unknown_persisted_event}}
      end
    end)
    |> case do
      {:ok, restored} -> {:ok, Enum.reverse(restored)}
      {:error, reason} -> {:error, reason}
    end
  end

  def attach_delivery_metadata(events, changes, version) do
    events
    |> Enum.with_index(1)
    |> Enum.map(fn {%Event{} = event, index} ->
      persisted_event = Map.fetch!(changes, {:event, index})
      %{event | delivery_id: persisted_event.id, version: version}
    end)
  end

  def persist_command(
        game_id,
        actor_id,
        %Command{} = command,
        %State{} = next_state,
        events
      )
      when is_list(events) do
    multi =
      Multi.new()
      |> Multi.run(:game, fn repo, _changes ->
        game =
          Game
          |> where([game], game.id == ^game_id)
          |> lock("FOR UPDATE")
          |> repo.one()

        cond do
          game == nil -> {:error, :game_not_found}
          game.current_version != command.expected_version -> {:error, :stale_version}
          game.status != "active" -> {:error, :game_not_active}
          true -> {:ok, game}
        end
      end)
      |> Multi.insert(:command, fn _changes ->
        %CommandRecord{
          game_id: game_id,
          command_id: command.command_id,
          actor_id: actor_id,
          command_type: Atom.to_string(command.type),
          payload_digest: payload_digest(command.payload),
          expected_version: command.expected_version,
          accepted_version: next_state.version,
          reply_json: %{"version" => next_state.version}
        }
        |> CommandRecord.insert_changeset()
      end)
      |> Multi.run(:last_sequence, fn repo, _changes ->
        sequence =
          GameEvent
          |> where([event], event.game_id == ^game_id)
          |> select([event], coalesce(max(event.sequence), 0))
          |> repo.one()

        {:ok, sequence}
      end)
      |> Multi.merge(fn %{last_sequence: last_sequence} ->
        event_multi(game_id, command.command_id, last_sequence, events)
      end)
      |> Multi.insert(:snapshot, snapshot_changeset(game_id, next_state))
      |> Multi.update(:updated_game, fn %{game: game} ->
        Game.transition_changeset(game, %{
          status: Atom.to_string(next_state.status),
          phase: Atom.to_string(next_state.phase),
          current_version: next_state.version
        })
      end)

    case Repo.transact(multi) do
      {:ok, changes} -> {:ok, changes}
      {:error, :game, reason, _changes} -> {:error, reason}
      {:error, :command, changeset, _changes} -> command_insert_error(changeset)
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def initial_records_multi(
        multi,
        game_id,
        actor_id,
        command_id,
        expected_version,
        %State{} = state
      ) do
    payload = %{}

    multi
    |> Multi.insert(:start_command, fn _changes ->
      %CommandRecord{
        game_id: game_id,
        command_id: command_id,
        actor_id: actor_id,
        command_type: "start_game",
        payload_digest: payload_digest(payload),
        expected_version: expected_version,
        accepted_version: state.version,
        reply_json: %{"version" => state.version}
      }
      |> CommandRecord.insert_changeset()
    end)
    |> Multi.insert(:initial_event, fn _changes ->
      %GameEvent{
        game_id: game_id,
        command_id: command_id,
        sequence: 1,
        event_type: "game_started",
        public_payload: %{
          "current_detective_id" => state.current_detective_id,
          "day" => state.day,
          "days_remaining" => state.days_remaining
        }
      }
      |> GameEvent.insert_changeset()
    end)
    |> Multi.insert(:initial_snapshot, snapshot_changeset(game_id, state))
  end

  def payload_digest(payload) do
    payload
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp event_multi(game_id, command_id, last_sequence, events) do
    events
    |> Enum.with_index(1)
    |> Enum.reduce(Multi.new(), fn {%Event{} = event, index}, multi ->
      event_name = {:event, index}
      sequence = last_sequence + index

      multi =
        Multi.insert(
          multi,
          event_name,
          %GameEvent{
            game_id: game_id,
            command_id: command_id,
            sequence: sequence,
            event_type: Atom.to_string(event.type),
            public_payload: SnapshotCodec.json_value(event.public_payload)
          }
          |> GameEvent.insert_changeset()
        )

      Enum.reduce(event.private_payloads, multi, fn {recipient_user_id, payload}, private_multi ->
        Multi.insert(private_multi, {:private_event, index, recipient_user_id}, fn changes ->
          persisted_event = Map.fetch!(changes, event_name)

          %GamePrivateEvent{
            game_id: game_id,
            game_event_id: persisted_event.id,
            recipient_user_id: recipient_user_id,
            payload: SnapshotCodec.json_value(payload)
          }
          |> GamePrivateEvent.insert_changeset()
        end)
      end)
    end)
  end

  defp snapshot_changeset(game_id, state) do
    %GameSnapshot{
      game_id: game_id,
      version: state.version,
      schema_version: State.schema_version(),
      state_json: SnapshotCodec.dump(state)
    }
    |> GameSnapshot.insert_changeset()
  end

  defp command_insert_error(changeset) do
    if Keyword.has_key?(changeset.errors, :command_id) do
      {:error, :duplicate_command}
    else
      {:error, changeset}
    end
  end
end
