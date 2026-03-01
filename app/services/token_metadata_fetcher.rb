# frozen_string_literal: true

# Fetches and persists ERC20 token metadata (decimals, symbol) from on-chain.
#
# Usage:
#   TokenMetadataFetcher.backfill(chain_id: 1)           # all tokens missing decimals
#   TokenMetadataFetcher.fetch_one(chain_id: 1, address: '0x...')
#
class TokenMetadataFetcher
  # Well-known mainnet tokens — skip RPC for these
  KNOWN_TOKENS = {
    '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' => { decimals: 18, symbol: 'WETH' },
    '0xdac17f958d2ee523a2206206994597c13d831ec7' => { decimals: 6,  symbol: 'USDT' },
    '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48' => { decimals: 6,  symbol: 'USDC' },
    '0x6b175474e89094c44da98b954eedeac495271d0f' => { decimals: 18, symbol: 'DAI' },
    '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599' => { decimals: 8,  symbol: 'WBTC' },
    '0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f' => { decimals: 18, symbol: 'SNX' },
    '0x514910771af9ca656af840dff83e8264ecf986ca' => { decimals: 18, symbol: 'LINK' },
    '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984' => { decimals: 18, symbol: 'UNI' },
    '0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9' => { decimals: 18, symbol: 'AAVE' },
  }.freeze

  class << self
    # Backfill all tokens missing decimals for a given chain
    # Pass rpc: to inject a custom RPC client (useful for testing)
    def backfill(chain_id: 1, batch_size: 100, rpc: nil)
      scope = TokenContract.where(chain_id: chain_id, decimals: nil)
      total = scope.count
      updated = 0
      failed = 0

      Rails.logger.info("[TokenMetadataFetcher] Starting backfill: #{total} tokens missing decimals on chain #{chain_id}")

      rpc ||= EthereumRpc.new(chain_id: chain_id)

      scope.find_each(batch_size: batch_size) do |token|
        addr = token.address.downcase
        known = KNOWN_TOKENS[addr]

        if known
          token.update!(decimals: known[:decimals], symbol: token.symbol.presence || known[:symbol])
          updated += 1
          next
        end

        begin
          metadata = rpc.get_token_metadata(addr)
          changes = {}
          changes[:decimals] = metadata[:decimals] if metadata[:decimals]
          changes[:symbol] = metadata[:symbol] if metadata[:symbol] && token.symbol.blank?
          changes[:name] = metadata[:name] if metadata[:name] && token.name.blank?

          if changes[:decimals]
            token.update!(changes)
            updated += 1
          else
            failed += 1
            Rails.logger.debug("[TokenMetadataFetcher] No decimals for #{addr}")
          end
        rescue => e
          failed += 1
          Rails.logger.warn("[TokenMetadataFetcher] Failed #{addr}: #{e.message}")
        end

        print '.' if (updated + failed) % 50 == 0
      end

      Rails.logger.info("[TokenMetadataFetcher] Done. Updated: #{updated}, Failed: #{failed}, Total: #{total}")
      { updated: updated, failed: failed, total: total }
    end

    # Fetch metadata for a single token
    # Pass rpc: to inject a custom RPC client (useful for testing)
    def fetch_one(chain_id:, address:, rpc: nil)
      addr = address.downcase
      token = TokenContract.find_or_create_for(addr, chain_id)
      return nil unless token

      known = KNOWN_TOKENS[addr]
      if known
        token.update!(decimals: known[:decimals], symbol: token.symbol.presence || known[:symbol])
        return token
      end

      rpc ||= EthereumRpc.new(chain_id: chain_id)
      metadata = rpc.get_token_metadata(addr)

      changes = {}
      changes[:decimals] = metadata[:decimals] if metadata[:decimals]
      changes[:symbol] = metadata[:symbol] if metadata[:symbol] && token.symbol.blank?
      changes[:name] = metadata[:name] if metadata[:name] && token.name.blank?
      token.update!(changes) if changes.any?

      token
    end
  end
end
