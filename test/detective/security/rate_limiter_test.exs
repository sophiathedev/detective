defmodule Detective.Security.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Detective.Security.RateLimiter

  test "limits a key inside a fixed window and allows it after expiry" do
    key = {:test, make_ref()}

    assert :ok = RateLimiter.check(key, limit: 2, window_ms: 100, now_ms: 1_000)
    assert :ok = RateLimiter.check(key, limit: 2, window_ms: 100, now_ms: 1_050)

    assert {:error, :rate_limited} =
             RateLimiter.check(key, limit: 2, window_ms: 100, now_ms: 1_099)

    assert :ok = RateLimiter.check(key, limit: 2, window_ms: 100, now_ms: 1_100)
  end

  test "keeps independent identities in separate buckets" do
    first_key = {:test, make_ref()}
    second_key = {:test, make_ref()}

    assert :ok = RateLimiter.check(first_key, limit: 1, window_ms: 100, now_ms: 2_000)

    assert {:error, :rate_limited} =
             RateLimiter.check(first_key, limit: 1, window_ms: 100, now_ms: 2_000)

    assert :ok = RateLimiter.check(second_key, limit: 1, window_ms: 100, now_ms: 2_000)
  end
end
