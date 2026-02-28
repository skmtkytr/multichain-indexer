# frozen_string_literal: true

module Decoders
  # Decodes Uniswap V2 PairCreated events to auto-register DEX pools.
  #
  # event PairCreated(address indexed token0, address indexed token1, address pair, uint)
  # topic0: 0x0d3648bd0f6ba80134a33ba9275ac585d9d315f0ad8355cddefde31afa28d0e9
  #
  # Also covers Sushiswap, Pancakeswap V2, and other V2 forks (same event sig).
  class UniswapV2PairCreatedDecoder
    TOPIC0 = '0x0d3648bd0f6ba80134a33ba9275ac585d9d315f0ad8355cddefde31afa28d0e9'

    # Known V2 factory addresses → DEX name (Ethereum mainnet)
    FACTORY_MAP = {
      '0x5c69bee701ef814a2b6a3edd4b1652cb9cc5aa6f' => 'uniswap_v2',
      '0xc0aee478e3658e2610c5f7a4a2e1777ce9e4f2ac' => 'sushiswap',
    }.freeze

    def self.decode_log(context, log, transfers)
      topics = log['topics'] || []
      return if topics.size < 3

      token0 = TransferDecoder.address_from_topic(topics[1])
      token1 = TransferDecoder.address_from_topic(topics[2])
      return unless token0 && token1

      data = log['data'] || '0x'
      raw = data.sub(/\A0x/, '')
      return if raw.length < 64

      pair_address = "0x#{raw[24, 40]}".downcase
      factory = log['address']&.downcase
      dex_name = FACTORY_MAP[factory] || 'uniswap_v2_like'

      DexPool.upsert(
        {
          chain_id:       context.chain_id,
          pool_address:   pair_address,
          dex_name:       dex_name,
          token0_address: token0,
          token1_address: token1,
          fee_tier:       30,  # V2 standard 0.3%
          created_at:     context.now,
          updated_at:     context.now
        },
        unique_by: %i[chain_id pool_address]
      )

      Rails.logger.debug { "DexPool registered: #{dex_name} #{pair_address} (#{token0}/#{token1})" }
    end
  end
end

TransferDecoder.register_log_decoder(
  Decoders::UniswapV2PairCreatedDecoder::TOPIC0,
  Decoders::UniswapV2PairCreatedDecoder
)
