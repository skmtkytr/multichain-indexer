# frozen_string_literal: true

# Plugin-based transfer decoder.
# Each decoder handles a specific event type and is registered via .register.
# New token standards can be added by creating a decoder class — no changes to core logic.
#
# Usage:
#   result = TransferDecoder.decode(chain_id:, block_number:, transactions:, logs:, withdrawals:)
#   result[:transfers]        # Array of transfer hashes (already upserted)
#   result[:token_addresses]  # Unique token addresses found
#   result[:count]            # Total transfer count
#
class TransferDecoder
  # Registry of log decoders keyed by topic0 hash
  @log_decoders = {}
  # Registry of non-log decoders (native tx, withdrawals, etc.)
  @extra_decoders = []

  class << self
    attr_reader :log_decoders, :extra_decoders

    # Register a decoder for a specific topic0 event signature
    def register_log_decoder(topic0, decoder_class)
      @log_decoders[topic0] = decoder_class
    end

    # Register a decoder for non-log sources (native tx value, beacon withdrawals)
    def register_extra_decoder(decoder_class)
      @extra_decoders << decoder_class
    end

    # Main entry point: decode all transfers from a block
    def decode(chain_id:, block_number:, transactions: [], logs: [], withdrawals: [])
      now = Time.current
      context = DecoderContext.new(chain_id: chain_id, block_number: block_number, now: now)
      transfers = []

      # 1. Run extra decoders (native ETH, beacon withdrawals, etc.)
      @extra_decoders.each do |decoder|
        decoder.decode(context, transactions: transactions, withdrawals: withdrawals, transfers: transfers)
      end

      # 2. Run log decoders (ERC-20, ERC-721, ERC-1155, WETH)
      logs.each do |log|
        topic0 = log['topics']&.first
        next unless topic0

        decoder = @log_decoders[topic0]
        next unless decoder

        decoder.decode_log(context, log, transfers)
      end

      # 3. Persist
      if transfers.any?
        AssetTransfer.upsert_all(transfers, unique_by: %i[chain_id tx_hash transfer_type log_index trace_index])
      end

      # 4. Persist DEX swaps
      if context.swaps.any?
        DexSwap.upsert_all(context.swaps, unique_by: %i[chain_id tx_hash log_index])
      end

      token_addresses = transfers.filter_map { |t| t[:token_address] }.uniq

      {
        transfers: transfers,
        token_addresses: token_addresses,
        count: transfers.size,
        swaps: context.swaps,
        swap_count: context.swaps.size
      }
    end
  end

  # Shared context passed to all decoders
  DecoderContext = Struct.new(:chain_id, :block_number, :now, :swaps, keyword_init: true) do
    def initialize(**kwargs)
      super
      self.swaps ||= []
    end

    def build_transfer(attrs)
      {
        block_number: block_number,
        chain_id: chain_id,
        log_index: -1,
        trace_index: -1,
        token_id: nil,
        token_address: nil,
        confidential: false,
        privacy_protocol: nil,
        created_at: now,
        updated_at: now
      }.merge(attrs)
    end
  end

  # ── Helper for parsing topics ──

  def self.address_from_topic(topic)
    return nil unless topic && topic.length >= 42
    "0x#{topic[-40..]}".downcase
  end
end
