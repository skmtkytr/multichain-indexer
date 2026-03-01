# frozen_string_literal: true

# Global token-bucket rate limiter for RPC endpoints.
# Thread-safe, keyed by RPC URL.
#
# Usage:
#   RpcRateLimiter.acquire("https://rpc.example.com")           # 1 token, blocks until available
#   RpcRateLimiter.acquire("https://rpc.example.com", tokens: 5) # batch of 5
#
class RpcRateLimiter
  DEFAULT_RPS = 15 # Conservative: leaves headroom below Chainstack's 25 RPS

  class Bucket
    attr_reader :rate, :tokens, :throttled_count, :total_requests

    def initialize(rate)
      @rate = rate.to_f
      @tokens = @rate
      @last_refill = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @mutex = Mutex.new
      @throttled_count = 0
      @total_requests = 0
    end

    # Acquire `n` tokens, sleeping if necessary. Returns wait time in seconds.
    def acquire(n = 1)
      waited = 0.0

      @mutex.synchronize do
        refill
        @total_requests += n

        if @tokens >= n
          @tokens -= n
          Rails.logger.debug("[RateLimiter] Acquired #{n} tokens, #{@tokens.round(1)} remaining") if defined?(Rails)
          return 0.0
        end

        # Need to wait for tokens
        @throttled_count += n
        deficit = n - @tokens
        wait_time = deficit / @rate
        Rails.logger.info("[RateLimiter] Throttling: need #{n} tokens, have #{@tokens.round(1)}, waiting #{wait_time.round(3)}s") if defined?(Rails)
        @tokens = 0
        waited = wait_time
      end

      # Sleep outside mutex so other threads aren't blocked longer than needed
      sleep(waited) if waited > 0

      # After sleeping, consume the tokens we waited for
      @mutex.synchronize do
        refill
        @tokens -= n
        @tokens = 0 if @tokens < 0 # safety
      end

      waited
    end

    # Current effective RPS (requests in last measurement window)
    def current_rps
      @mutex.synchronize { @rate }
    end

    def stats
      @mutex.synchronize do
        {
          rate: @rate,
          available_tokens: @tokens.floor,
          throttled_count: @throttled_count,
          total_requests: @total_requests
        }
      end
    end

    private

    def refill
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      elapsed = now - @last_refill
      @tokens = [@tokens + elapsed * @rate, @rate].min
      @last_refill = now
    end
  end

  class << self
    private

    def global_mutex
      $rpc_rate_limiter_mutex ||= Mutex.new
    end

    def buckets
      $rpc_rate_limiter_buckets ||= {}
    end

    public
    # Acquire tokens for the given RPC URL.
    # rate: override RPS for this URL (cached on first call per URL)
    def acquire(rpc_url, tokens: 1, rate: nil)
      bucket = bucket_for(rpc_url, rate: rate)
      bucket.acquire(tokens)
    end

    # Get or create a bucket for the given URL.
    def bucket_for(rpc_url, rate: nil)
      global_mutex.synchronize do
        buckets[rpc_url] ||= Bucket.new(rate || DEFAULT_RPS)
      end
    end

    # Stats for a specific URL
    def stats(rpc_url)
      global_mutex.synchronize do
        buckets[rpc_url]&.stats
      end
    end

    # Stats for all URLs
    def all_stats
      global_mutex.synchronize do
        buckets.transform_values(&:stats)
      end
    end

    # Reset all buckets (useful for testing)
    def reset!
      global_mutex.synchronize do
        buckets.clear
      end
    end
  end
end
