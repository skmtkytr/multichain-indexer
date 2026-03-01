# frozen_string_literal: true

require 'ostruct'

# Detects arbitrage opportunities from DEX swaps within a block.
#
# Strategy: For each token pair with swaps on multiple pools in the same block,
# compare effective prices. If spread > threshold, record opportunity.
#
# Usage:
#   ArbDetector.analyze_block(chain_id: 1, block_number: 12345)
#   ArbDetector.analyze_swaps(chain_id: 1, block_number: 12345, swaps: [...])
#
class ArbDetector
  # Minimum spread in basis points to record as opportunity
  MIN_SPREAD_BPS = 5  # 0.05%

  # Minimum swap value in the "base" token (pair[0]) after decimal normalization.
  # Swaps below this threshold are excluded — too small to be meaningful for arb.
  # This filters out dust trades that produce unreliable prices.
  MIN_SWAP_VALUE_BASE = BigDecimal('0.001')  # e.g., 0.001 WBTC (~$95), 0.001 WETH (~$2)

  class << self
    # Analyze a block that's already indexed — reads from DB
    def analyze_block(chain_id:, block_number:)
      swaps = DexSwap.for_block(chain_id, block_number).to_a
      return [] if swaps.size < 2

      detect_direct_arb(chain_id, block_number, swaps)
    end

    # Analyze from in-memory swap data (called during block processing)
    def analyze_swaps(chain_id:, block_number:, swaps:)
      return [] if swaps.size < 2

      # Convert hash swaps to OpenStruct for uniform access
      swap_objects = swaps.map { |s| s.is_a?(Hash) ? OpenStruct.new(s) : s }
      detect_direct_arb(chain_id, block_number, swap_objects)
    end

    # Compute decimal-normalized price: amount_out / amount_in adjusted for decimals.
    # Returns nil if either adjusted amount is zero.
    def normalized_price(amount_in, amount_out, decimals_in, decimals_out)
      adj_in  = BigDecimal(amount_in.to_s) / BigDecimal(10)**decimals_in
      adj_out = BigDecimal(amount_out.to_s) / BigDecimal(10)**decimals_out
      return nil if adj_in.zero? || adj_out.zero?

      adj_out / adj_in
    end

    private

    # In-memory decimals cache: address -> Integer (or nil)
    def decimals_cache
      @decimals_cache ||= {}
    end

    # Look up decimals for a token address, with in-memory caching.
    # Returns Integer decimals or nil if unknown.
    def fetch_decimals(chain_id, address)
      addr = address.downcase
      cache_key = "#{chain_id}:#{addr}"

      return decimals_cache[cache_key] if decimals_cache.key?(cache_key)

      # Check well-known tokens first (mainnet only)
      if chain_id == 1 && TokenMetadataFetcher::KNOWN_TOKENS.key?(addr)
        dec = TokenMetadataFetcher::KNOWN_TOKENS[addr][:decimals]
        decimals_cache[cache_key] = dec
        return dec
      end

      tc = TokenContract.find_by(address: addr, chain_id: chain_id)
      dec = tc&.decimals
      decimals_cache[cache_key] = dec
      dec
    end

    # Clear the decimals cache (useful for testing)
    def clear_decimals_cache!
      @decimals_cache = {}
    end

    # Direct arbitrage: same token pair, different pools, different prices
    def detect_direct_arb(chain_id, block_number, swaps)
      opportunities = []

      # Group swaps by normalized token pair (sorted addresses)
      by_pair = swaps.group_by do |s|
        next nil unless s.token_in && s.token_out
        [s.token_in, s.token_out].sort
      end
      by_pair.delete(nil)

      by_pair.each do |pair, pair_swaps|
        # Need swaps on at least 2 different pools
        by_pool = pair_swaps.group_by(&:pool_address)
        next if by_pool.size < 2

        # Fetch decimals for this pair
        dec0 = fetch_decimals(chain_id, pair[0])
        dec1 = fetch_decimals(chain_id, pair[1])

        # Skip pairs where decimals are unknown (prevents false positives)
        if dec0.nil? || dec1.nil?
          Rails.logger.debug("[ArbDetector] Skipping pair #{pair[0]}/#{pair[1]}: decimals unknown (#{dec0.inspect}/#{dec1.inspect})")
          next
        end

        # For each pool, compute volume-weighted average price (VWAP)
        # normalized as: pair[1] amount / pair[0] amount (both decimal-adjusted)
        pool_prices = {}
        by_pool.each do |pool_addr, pool_swaps|
          total_base = BigDecimal('0')  # sum of pair[0] token amounts (decimal-adjusted)
          total_quote = BigDecimal('0') # sum of pair[1] token amounts (decimal-adjusted)

          pool_swaps.each do |s|
            next unless s.amount_in.to_i > 0 && s.amount_out.to_i > 0

            if s.token_in == pair[0]
              base_adj  = BigDecimal(s.amount_in.to_s) / BigDecimal(10)**dec0
              quote_adj = BigDecimal(s.amount_out.to_s) / BigDecimal(10)**dec1
            else
              base_adj  = BigDecimal(s.amount_out.to_s) / BigDecimal(10)**dec0
              quote_adj = BigDecimal(s.amount_in.to_s) / BigDecimal(10)**dec1
            end

            # Skip dust trades — unreliable prices
            next if base_adj < MIN_SWAP_VALUE_BASE

            total_base += base_adj
            total_quote += quote_adj
          end

          # Skip pools with no qualifying swaps
          next if total_base.zero?

          vwap = total_quote / total_base
          pool_prices[pool_addr] = {
            price: vwap,
            volume_base: total_base,
            dex_name: pool_swaps.first.dex_name,
            tx_hash: pool_swaps.last.tx_hash
          }
        end

        next if pool_prices.size < 2

        # Find min/max price pools
        sorted = pool_prices.sort_by { |_, v| v[:price] }
        low_pool, low_data = sorted.first
        high_pool, high_data = sorted.last

        # Calculate spread in basis points
        mid = (low_data[:price] + high_data[:price]) / 2
        next if mid.zero?

        spread_bps = ((high_data[:price] - low_data[:price]) / mid * 10_000).to_f

        next if spread_bps < MIN_SPREAD_BPS

        # Same-TX swaps = someone already executed this arb (flashloan/multi-hop)
        same_tx = low_data[:tx_hash] == high_data[:tx_hash]

        # Estimate profit: use the smaller pool's volume as max executable size
        # Profit ≈ min_volume × spread (in quote token terms)
        min_volume = [low_data[:volume_base], high_data[:volume_base]].min
        est_profit_quote = min_volume * (high_data[:price] - low_data[:price])

        opportunities << {
          chain_id:             chain_id,
          block_number:         block_number,
          token_in:             pair[0],
          token_bridge:         nil,
          pool_buy:             low_pool,
          pool_sell:            high_pool,
          dex_buy:              low_data[:dex_name],
          dex_sell:             high_data[:dex_name],
          price_buy:            low_data[:price],
          price_sell:           high_data[:price],
          spread_bps:           spread_bps.round(2),
          estimated_profit_wei: est_profit_quote,
          arb_type:             'direct',
          tx_hash_buy:          low_data[:tx_hash],
          tx_hash_sell:         high_data[:tx_hash],
          executed:             same_tx,
          created_at:           Time.current,
          updated_at:           Time.current
        }
      end

      # Persist
      if opportunities.any?
        ArbOpportunity.insert_all(opportunities)
      end

      opportunities
    end
  end
end
