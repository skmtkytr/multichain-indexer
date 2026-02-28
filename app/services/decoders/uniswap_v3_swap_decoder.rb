# frozen_string_literal: true

module Decoders
  # Decodes Uniswap V3 Swap events.
  #
  # event Swap(address indexed sender, address indexed recipient,
  #            int256 amount0, int256 amount1,
  #            uint160 sqrtPriceX96, uint128 liquidity, int24 tick)
  #
  # topic0: 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67
  # topics[1]: sender
  # topics[2]: recipient
  # data: amount0 (int256) | amount1 (int256) | sqrtPriceX96 (uint160) | liquidity (uint128) | tick (int24)
  class UniswapV3SwapDecoder
    TOPIC0 = '0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67'

    DEX_NAME = 'uniswap_v3'

    def self.decode_log(context, log, transfers)
      topics = log['topics'] || []
      return if topics.size < 3

      data = log['data'] || '0x'
      raw = data.sub(/\A0x/, '')
      return if raw.length < 320  # 5 x 32 bytes

      sender    = TransferDecoder.address_from_topic(topics[1])
      recipient = TransferDecoder.address_from_topic(topics[2])
      pool_addr = log['address']&.downcase

      # amount0 and amount1 are int256 (signed)
      amount0 = decode_int256(raw[0, 64])
      amount1 = decode_int256(raw[64, 64])
      sqrt_price_x96 = raw[128, 64].to_i(16)
      # liquidity = raw[192, 64].to_i(16)  # not stored for now
      tick = decode_int256(raw[256, 64])

      pool = DexPool.cached_find(context.chain_id, pool_addr)

      # Auto-register unknown V3 pools
      if pool.nil?
        pool = auto_register_v3_pool(context.chain_id, pool_addr)
      end

      # In V3: negative amount = token leaves pool (= output to user)
      #         positive amount = token enters pool (= input from user)
      if amount0 > 0 && amount1 < 0
        # token0 in, token1 out
        amount_in  = amount0
        amount_out = amount1.abs
        token_in   = pool&.token0_address
        token_out  = pool&.token1_address
      elsif amount1 > 0 && amount0 < 0
        # token1 in, token0 out
        amount_in  = amount1
        amount_out = amount0.abs
        token_in   = pool&.token1_address
        token_out  = pool&.token0_address
      else
        return  # shouldn't happen in normal swaps
      end

      log_idx = log['logIndex']&.to_i(16) || -1
      tx_hash = log['transactionHash']

      price = amount_in > 0 ? BigDecimal(amount_out.to_s) / BigDecimal(amount_in.to_s) : nil

      swap = {
        chain_id:       context.chain_id,
        block_number:   context.block_number,
        tx_hash:        tx_hash,
        log_index:      log_idx,
        pool_address:   pool_addr,
        dex_name:       pool&.dex_name || DEX_NAME,
        sender:         sender,
        recipient:      recipient,
        token_in:       token_in,
        token_out:      token_out,
        amount_in:      amount_in.to_s,
        amount_out:     amount_out.to_s,
        price:          price&.to_f,
        sqrt_price_x96: sqrt_price_x96.to_s,
        tick:           tick,
        created_at:     context.now,
        updated_at:     context.now
      }

      context.swaps << swap
    end

    # Decode a 64-hex-char int256 (two's complement)
    def self.decode_int256(hex)
      val = hex.to_i(16)
      val >= (1 << 255) ? val - (1 << 256) : val
    end

    # Query token0(), token1(), fee() from V3 pool contract
    def self.auto_register_v3_pool(chain_id, pool_address)
      rpc = EthereumRpc.new(chain_id: chain_id)

      # token0(): 0x0dfe1681, token1(): 0xd21220a7, fee(): 0xddca3f43
      results = rpc.batch_call([
        { method: 'eth_call', params: [{ to: pool_address, data: '0x0dfe1681' }, 'latest'] },
        { method: 'eth_call', params: [{ to: pool_address, data: '0xd21220a7' }, 'latest'] },
        { method: 'eth_call', params: [{ to: pool_address, data: '0xddca3f43' }, 'latest'] }
      ])

      return nil unless results&.size == 3
      token0_raw, token1_raw, fee_raw = results
      return nil unless token0_raw.is_a?(String) && token0_raw.length >= 66
      return nil unless token1_raw.is_a?(String) && token1_raw.length >= 66

      token0 = "0x#{token0_raw[-40..]}".downcase
      token1 = "0x#{token1_raw[-40..]}".downcase
      fee = fee_raw.is_a?(String) ? fee_raw.to_i(16) : nil

      # Fetch symbols
      sym0, sym1 = Decoders::UniswapV2SwapDecoder.fetch_token_symbols(rpc, token0, token1)

      pool = DexPool.create!(
        chain_id: chain_id,
        pool_address: pool_address,
        dex_name: DEX_NAME,
        token0_address: token0,
        token1_address: token1,
        token0_symbol: sym0,
        token1_symbol: sym1,
        fee_tier: fee
      )

      Rails.logger.info("Auto-registered V3 pool: #{pool_address} (#{sym0 || token0}/#{sym1 || token1}) fee=#{fee}")
      pool
    rescue StandardError => e
      Rails.logger.debug("Failed to auto-register V3 pool #{pool_address}: #{e.message}")
      nil
    end
  end
end

TransferDecoder.register_log_decoder(
  Decoders::UniswapV3SwapDecoder::TOPIC0,
  Decoders::UniswapV3SwapDecoder
)
