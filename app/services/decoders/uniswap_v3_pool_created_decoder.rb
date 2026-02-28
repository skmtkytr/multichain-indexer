# frozen_string_literal: true

module Decoders
  # Decodes Uniswap V3 PoolCreated events to auto-register DEX pools.
  #
  # event PoolCreated(address indexed token0, address indexed token1,
  #                   uint24 indexed fee, int24 tickSpacing, address pool)
  # topic0: 0x783cca1c0412dd0d695e784568c96da2e9c22ff989357a2e8b1d9b2b4e6b7118
  class UniswapV3PoolCreatedDecoder
    TOPIC0 = '0x783cca1c0412dd0d695e784568c96da2e9c22ff989357a2e8b1d9b2b4e6b7118'

    # Known V3 factory addresses (Ethereum mainnet)
    FACTORY_MAP = {
      '0x1f98431c8ad98523631ae4a59f267346ea31f984' => 'uniswap_v3',
    }.freeze

    def self.decode_log(context, log, transfers)
      topics = log['topics'] || []
      return if topics.size < 4

      token0 = TransferDecoder.address_from_topic(topics[1])
      token1 = TransferDecoder.address_from_topic(topics[2])
      fee = topics[3].to_i(16)  # fee in hundredths of a bip (e.g., 3000 = 0.3%)
      return unless token0 && token1

      data = log['data'] || '0x'
      raw = data.sub(/\A0x/, '')
      return if raw.length < 128  # tickSpacing (32B) + pool address (32B)

      # tickSpacing = raw[0, 64]  # not stored
      pool_address = "0x#{raw[88, 40]}".downcase
      factory = log['address']&.downcase
      dex_name = FACTORY_MAP[factory] || 'uniswap_v3_like'

      DexPool.upsert(
        {
          chain_id:       context.chain_id,
          pool_address:   pool_address,
          dex_name:       dex_name,
          token0_address: token0,
          token1_address: token1,
          fee_tier:       fee,
          created_at:     context.now,
          updated_at:     context.now
        },
        unique_by: %i[chain_id pool_address]
      )

      Rails.logger.debug { "DexPool registered: #{dex_name} #{pool_address} (#{token0}/#{token1}) fee=#{fee}" }
    end
  end
end

TransferDecoder.register_log_decoder(
  Decoders::UniswapV3PoolCreatedDecoder::TOPIC0,
  Decoders::UniswapV3PoolCreatedDecoder
)
