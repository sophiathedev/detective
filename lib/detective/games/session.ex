defmodule Detective.Games.Session do
  use GenServer

  alias Detective.Games.{
    Command,
    ConnectionMonitor,
    Engine,
    GameBroadcaster,
    Persistence,
    SessionSupervisor
  }

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via(game_id))
  end

  def child_spec(game_id) do
    %{
      id: {__MODULE__, game_id},
      start: {__MODULE__, :start_link, [game_id]},
      restart: :permanent,
      type: :worker
    }
  end

  def execute(game_id, actor_id, %Command{} = command) do
    session_call(game_id, {:execute, actor_id, command}, 15_000, 1)
  end

  def get_state(game_id) do
    session_call(game_id, :get_state, 5_000, 1)
  end

  def pause_for_disconnect(game_id, player_ids) do
    session_call(game_id, {:pause_for_disconnect, player_ids}, 15_000, 1)
  end

  def request_pause_for_disconnect(game_id, player_ids) do
    with {:ok, pid} <- SessionSupervisor.ensure_session(game_id) do
      GenServer.cast(pid, {:pause_for_disconnect, player_ids})
      :ok
    end
  end

  def via(game_id), do: {:via, Registry, {Detective.GameRegistry, game_id}}

  @impl true
  def init(game_id) do
    case Persistence.load_state(game_id) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, {:ok, state}, state}

  def handle_call({:pause_for_disconnect, player_ids}, _from, state) do
    case pause_for_disconnect_transition(state, player_ids) do
      {:ok, reply, next_state} -> {:reply, {:ok, reply}, next_state}
      {:error, reason, next_state} -> {:reply, {:error, reason}, next_state}
    end
  end

  def handle_call({:execute, actor_id, command}, _from, state) do
    case Persistence.lookup_command(state.game_id, command.command_id) do
      nil ->
        execute_new_command(state, actor_id, command)

      record ->
        if Persistence.command_matches?(record, actor_id, command) do
          case Persistence.events_for_command(
                 state.game_id,
                 command.command_id,
                 record.accepted_version
               ) do
            {:ok, events} ->
              reply = %{
                version: record.accepted_version,
                duplicate: true,
                events: events,
                state: state
              }

              {:reply, {:ok, reply}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          {:reply, {:error, :command_id_conflict}, state}
        end
    end
  end

  @impl true
  def handle_cast({:pause_for_disconnect, player_ids}, state) do
    case pause_for_disconnect_transition(state, player_ids) do
      {:ok, %{events: []}, next_state} ->
        {:noreply, next_state}

      {:ok, reply, next_state} ->
        :ok = GameBroadcaster.broadcast(reply.state, reply.events)
        {:noreply, next_state}

      {:error, _reason, next_state} ->
        {:noreply, next_state}
    end
  end

  defp execute_new_command(state, actor_id, command) do
    with :ok <- validate_connection_gate(state, command),
         {:ok, next_state, events} <- Engine.apply(state, actor_id, command),
         {:ok, changes} <-
           Persistence.persist_command(state.game_id, actor_id, command, next_state, events) do
      events = Persistence.attach_delivery_metadata(events, changes, next_state.version)

      :ok =
        ConnectionMonitor.game_status_changed(
          state.game_id,
          next_state.status,
          next_state.version
        )

      reply = %{
        version: next_state.version,
        duplicate: false,
        events: events,
        state: next_state
      }

      {:reply, {:ok, reply}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp pause_for_disconnect_transition(state, player_ids) do
    case Engine.apply_system(state, {:pause_for_disconnect, player_ids}) do
      {:ok, _next_state, []} ->
        {:ok, %{version: state.version, events: [], state: state}, state}

      {:ok, next_state, events} ->
        transition_id = Ecto.UUID.generate()

        with {:ok, changes} <-
               Persistence.persist_system_transition(
                 state.game_id,
                 state.version,
                 transition_id,
                 next_state,
                 events,
                 "active"
               ) do
          events = Persistence.attach_delivery_metadata(events, changes, next_state.version)

          :ok =
            ConnectionMonitor.game_status_changed(
              state.game_id,
              next_state.status,
              next_state.version
            )

          {:ok,
           %{
             version: next_state.version,
             events: events,
             state: next_state
           }, next_state}
        else
          {:error, reason} -> {:error, reason, state}
        end
    end
  end

  defp validate_connection_gate(state, %Command{type: :resume_game}) do
    with {:ok, _pid} <-
           ConnectionMonitor.ensure_monitor(
             state.game_id,
             Map.keys(state.players),
             state.status,
             state.version
           ),
         true <- ConnectionMonitor.all_players_online?(state.game_id) do
      :ok
    else
      _reason -> {:error, :players_offline}
    end
  end

  defp validate_connection_gate(_state, _command), do: :ok

  defp session_call(game_id, message, timeout, attempts_left) do
    with {:ok, pid} <- SessionSupervisor.ensure_session(game_id) do
      try do
        GenServer.call(pid, message, timeout)
      catch
        :exit, _reason when attempts_left > 0 ->
          session_call(game_id, message, timeout, attempts_left - 1)

        :exit, _reason ->
          {:error, :session_unavailable}
      end
    end
  end
end
