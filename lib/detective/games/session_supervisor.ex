defmodule Detective.Games.SessionSupervisor do
  use DynamicSupervisor

  alias Detective.Games.Session

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg), do: DynamicSupervisor.init(strategy: :one_for_one)

  def ensure_session(game_id) do
    case Registry.lookup(Detective.GameRegistry, game_id) do
      [{pid, _value}] ->
        if Process.alive?(pid), do: {:ok, pid}, else: start_session(game_id, 2)

      [] ->
        start_session(game_id, 2)
    end
  end

  defp start_session(game_id, attempts_left) do
    case DynamicSupervisor.start_child(__MODULE__, {Session, game_id}) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        cond do
          Process.alive?(pid) ->
            {:ok, pid}

          attempts_left > 0 ->
            _ = :sys.get_state(__MODULE__)
            start_session(game_id, attempts_left - 1)

          true ->
            {:error, :session_unavailable}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
