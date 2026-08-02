defmodule Detective.Games.Session do
  use GenServer

  alias Detective.Games.{Command, Engine, Persistence, SessionSupervisor}

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
    with {:ok, pid} <- SessionSupervisor.ensure_session(game_id) do
      GenServer.call(pid, {:execute, actor_id, command}, 15_000)
    end
  end

  def get_state(game_id) do
    with {:ok, pid} <- SessionSupervisor.ensure_session(game_id) do
      GenServer.call(pid, :get_state)
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

  def handle_call({:execute, actor_id, command}, _from, state) do
    case Persistence.lookup_command(state.game_id, command.command_id) do
      nil ->
        execute_new_command(state, actor_id, command)

      record ->
        if Persistence.command_matches?(record, actor_id, command) do
          reply = %{
            version: record.accepted_version,
            duplicate: true,
            events: []
          }

          {:reply, {:ok, reply}, state}
        else
          {:reply, {:error, :command_id_conflict}, state}
        end
    end
  end

  defp execute_new_command(state, actor_id, command) do
    with {:ok, next_state, events} <- Engine.apply(state, actor_id, command),
         {:ok, _changes} <-
           Persistence.persist_command(state.game_id, actor_id, command, next_state, events) do
      reply = %{
        version: next_state.version,
        duplicate: false,
        events: events
      }

      {:reply, {:ok, reply}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end
