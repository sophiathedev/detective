defmodule Detective.Security.RateLimiter do
  @moduledoc false

  use GenServer

  @sweep_interval_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  def check(key, opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)
    window_ms = Keyword.get(opts, :window_ms, 2_000)
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)

    if is_integer(limit) and limit > 0 and is_integer(window_ms) and window_ms > 0 and
         is_integer(now_ms) do
      GenServer.call(__MODULE__, {:check, key, limit, window_ms, now_ms})
    else
      {:error, :invalid_rate_limit}
    end
  end

  @impl true
  def init(_init_arg) do
    {:ok, %{buckets: %{}, last_sweep_ms: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_call({:check, key, limit, window_ms, now_ms}, _from, state) do
    state = maybe_sweep(state, now_ms)

    case Map.get(state.buckets, key) do
      {started_at_ms, count, bucket_window_ms}
      when now_ms - started_at_ms < bucket_window_ms and count >= limit ->
        {:reply, {:error, :rate_limited}, state}

      {started_at_ms, count, bucket_window_ms}
      when now_ms - started_at_ms < bucket_window_ms ->
        bucket = {started_at_ms, count + 1, bucket_window_ms}
        {:reply, :ok, put_in(state.buckets[key], bucket)}

      _missing_or_expired ->
        {:reply, :ok, put_in(state.buckets[key], {now_ms, 1, window_ms})}
    end
  end

  defp maybe_sweep(state, now_ms) do
    if now_ms - state.last_sweep_ms >= @sweep_interval_ms do
      buckets =
        Map.reject(state.buckets, fn {_key, {started_at_ms, _count, window_ms}} ->
          now_ms - started_at_ms >= max(window_ms, @sweep_interval_ms)
        end)

      %{state | buckets: buckets, last_sweep_ms: now_ms}
    else
      state
    end
  end
end
