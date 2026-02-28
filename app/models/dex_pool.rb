# frozen_string_literal: true

class DexPool < ApplicationRecord
  validates :chain_id, :pool_address, :dex_name, :token0_address, :token1_address, presence: true
  validates :pool_address, uniqueness: { scope: :chain_id }

  # In-memory cache: pool_address -> DexPool
  @cache = {}
  @cache_mutex = Mutex.new

  class << self
    def cached_find(chain_id, pool_address)
      key = "#{chain_id}:#{pool_address}"
      @cache_mutex.synchronize do
        cached = @cache[key]
        return cached[:pool] if cached && cached[:expires_at] > Time.current
      end

      pool = find_by(chain_id: chain_id, pool_address: pool_address)
      if pool
        @cache_mutex.synchronize do
          @cache[key] = { pool: pool, expires_at: 5.minutes.from_now }
        end
      end
      pool
    end

    def invalidate_cache!
      @cache_mutex.synchronize { @cache.clear }
    end
  end

  after_commit :invalidate_cache

  # Returns the other token given one side
  def other_token(token_address)
    token_address.downcase == token0_address ? token1_address : token0_address
  end

  # Check if pool contains given token
  def has_token?(token_address)
    addr = token_address.downcase
    token0_address == addr || token1_address == addr
  end

  private

  def invalidate_cache
    self.class.invalidate_cache!
  end
end
