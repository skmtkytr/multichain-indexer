# frozen_string_literal: true

require 'test_helper'

class RpcRateLimiterTest < ActiveSupport::TestCase
  setup do
    RpcRateLimiter.reset!
  end

  test "acquire consumes tokens" do
    url = "https://test-rpc.example.com"
    bucket = RpcRateLimiter.bucket_for(url, rate: 100)

    # Should not block at high rate
    waited = RpcRateLimiter.acquire(url, tokens: 1)
    assert_equal 0.0, waited

    stats = RpcRateLimiter.stats(url)
    assert_equal 1, stats[:total_requests]
    assert_equal 0, stats[:throttled_count]
  end

  test "acquire blocks when tokens exhausted" do
    url = "https://slow-rpc.example.com"
    # Very low rate: 10 tokens/sec
    RpcRateLimiter.bucket_for(url, rate: 10)

    # Consume all tokens at once
    RpcRateLimiter.acquire(url, tokens: 10)

    # Next acquire should block
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    RpcRateLimiter.acquire(url, tokens: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    # Should have waited ~0.1s (1 token / 10 rps)
    assert elapsed >= 0.05, "Expected to wait but elapsed was #{elapsed}s"

    stats = RpcRateLimiter.stats(url)
    assert stats[:throttled_count] > 0
  end

  test "different URLs get independent buckets" do
    url_a = "https://rpc-a.example.com"
    url_b = "https://rpc-b.example.com"

    RpcRateLimiter.acquire(url_a, rate: 50)
    RpcRateLimiter.acquire(url_b, rate: 100)

    stats_a = RpcRateLimiter.stats(url_a)
    stats_b = RpcRateLimiter.stats(url_b)

    assert_equal 50, stats_a[:rate]
    assert_equal 100, stats_b[:rate]
  end

  test "default rate is 15 RPS" do
    url = "https://default-rpc.example.com"
    RpcRateLimiter.acquire(url)
    stats = RpcRateLimiter.stats(url)
    assert_equal 15.0, stats[:rate]
  end

  test "batch token acquisition" do
    url = "https://batch-rpc.example.com"
    RpcRateLimiter.bucket_for(url, rate: 100)
    RpcRateLimiter.acquire(url, tokens: 5)

    stats = RpcRateLimiter.stats(url)
    assert_equal 5, stats[:total_requests]
  end

  test "thread safety - concurrent acquires" do
    url = "https://threaded-rpc.example.com"
    RpcRateLimiter.bucket_for(url, rate: 1000)

    threads = 10.times.map do
      Thread.new do
        20.times { RpcRateLimiter.acquire(url) }
      end
    end
    threads.each(&:join)

    stats = RpcRateLimiter.stats(url)
    assert_equal 200, stats[:total_requests]
  end

  test "reset clears all buckets" do
    RpcRateLimiter.acquire("https://a.com")
    RpcRateLimiter.reset!
    assert_nil RpcRateLimiter.stats("https://a.com")
  end

  # ── all_stats ──

  test "all_stats returns stats for all buckets" do
    RpcRateLimiter.acquire("https://x.com", rate: 30)
    RpcRateLimiter.acquire("https://y.com", rate: 40)

    all = RpcRateLimiter.all_stats
    assert_equal 2, all.size
    assert_equal 30, all["https://x.com"][:rate]
    assert_equal 40, all["https://y.com"][:rate]
  end

  test "all_stats empty when no buckets" do
    assert_equal({}, RpcRateLimiter.all_stats)
  end

  # ── rate-specified bucket creation ──

  test "bucket_for creates bucket with specified rate" do
    bucket = RpcRateLimiter.bucket_for("https://custom.com", rate: 75)
    assert_equal 75, bucket.rate
  end

  test "bucket_for reuses existing bucket" do
    b1 = RpcRateLimiter.bucket_for("https://reuse.com", rate: 50)
    b2 = RpcRateLimiter.bucket_for("https://reuse.com", rate: 99)  # ignored
    assert_same b1, b2
    assert_equal 50, b2.rate  # original rate kept
  end

  # ── consecutive acquire token drain ──

  test "consecutive acquires drain tokens" do
    url = "https://drain.com"
    RpcRateLimiter.bucket_for(url, rate: 100)

    5.times { RpcRateLimiter.acquire(url, tokens: 1) }

    stats = RpcRateLimiter.stats(url)
    assert_equal 5, stats[:total_requests]
    # Available tokens should be less than 100
    assert stats[:available_tokens] < 100
  end
end
