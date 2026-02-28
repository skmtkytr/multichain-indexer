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

    private

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

        # For each pool, compute average effective price (normalized: token_pair[0] → token_pair[1])
        pool_prices = {}
        by_pool.each do |pool_addr, pool_swaps|
          prices = pool_swaps.filter_map do |s|
            next nil unless s.amount_in.to_i > 0 && s.amount_out.to_i > 0

            # Normalize: price = pair[1] amount / pair[0] amount
            if s.token_in == pair[0]
              BigDecimal(s.amount_out.to_s) / BigDecimal(s.amount_in.to_s)
            else
              BigDecimal(s.amount_in.to_s) / BigDecimal(s.amount_out.to_s)
            end
          end
          next if prices.empty?

          avg_price = prices.sum / prices.size
          pool_prices[pool_addr] = {
            price: avg_price,
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

        opportunities << {
          chain_id:             chain_id,
          block_number:         block_number,
          token_in:             pair[0],
          token_bridge:         nil,
          pool_buy:             low_pool,
          pool_sell:            high_pool,
          dex_buy:              low_data[:dex_name],
          dex_sell:             high_data[:dex_name],
          price_buy:            low_data[:price].to_f,
          price_sell:           high_data[:price].to_f,
          spread_bps:           spread_bps.round(2),
          estimated_profit_wei: nil,  # TODO: estimate with liquidity depth
          arb_type:             'direct',
          tx_hash_buy:          low_data[:tx_hash],
          tx_hash_sell:         high_data[:tx_hash],
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
