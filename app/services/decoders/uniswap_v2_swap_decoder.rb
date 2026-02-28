# frozen_string_literal: true

module Decoders
  # Decodes Uniswap V2 (and forks: Sushiswap, Pancakeswap, etc.) Swap events.
  #
  # event Swap(address indexed sender, uint256 amount0In, uint256 amount1In,
  #            uint256 amount0Out, uint256 amount1Out, address indexed to)
  #
  # topic0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
  # topics[1]: sender
  # topics[2]: to (recipient)
  # data: amount0In (32B) | amount1In (32B) | amount0Out (32B) | amount1Out (32B)
  class UniswapV2SwapDecoder
    TOPIC0 = '0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822'

    # Known V2-style DEX factory → name mapping
    # Pool lookup resolves the DEX name; fallback to 'uniswap_v2_like'
    DEX_NAME = 'uniswap_v2'

    def self.decode_log(context, log, transfers)
      topics = log['topics'] || []
      return if topics.size < 3

      data = log['data'] || '0x'
      raw = data.sub(/\A0x/, '')
      return if raw.length < 256  # need 4 x 32 bytes = 256 hex chars

      sender    = TransferDecoder.address_from_topic(topics[1])
      recipient = TransferDecoder.address_from_topic(topics[2])
      pool_addr = log['address']&.downcase

      amount0_in  = raw[0, 64].to_i(16)
      amount1_in  = raw[64, 64].to_i(16)
      amount0_out = raw[128, 64].to_i(16)
      amount1_out = raw[192, 64].to_i(16)

      # Determine swap direction
      # If amount0In > 0 && amount1Out > 0 → token0 in, token1 out
      # If amount1In > 0 && amount0Out > 0 → token1 in, token0 out
      pool = DexPool.cached_find(context.chain_id, pool_addr)

      # Auto-register unknown V2 pools by querying token0/token1 on-chain
      if pool.nil?
        pool = auto_register_v2_pool(context.chain_id, pool_addr)
      end

      if amount0_in > 0 && amount1_out > 0
        amount_in  = amount0_in
        amount_out = amount1_out
        token_in   = pool&.token0_address
        token_out  = pool&.token1_address
      elsif amount1_in > 0 && amount0_out > 0
        amount_in  = amount1_in
        amount_out = amount0_out
        token_in   = pool&.token1_address
        token_out  = pool&.token0_address
      else
        # Edge case: both sides have in amounts (multi-hop in single event, rare)
        amount_in  = [amount0_in, amount1_in].max
        amount_out = [amount0_out, amount1_out].max
        token_in   = pool&.token0_address
        token_out  = pool&.token1_address
      end

      log_idx = log['logIndex']&.to_i(16) || -1
      tx_hash = log['transactionHash']

      # Calculate price ratio (raw, not decimal-adjusted)
      price = amount_in > 0 ? BigDecimal(amount_out.to_s) / BigDecimal(amount_in.to_s) : nil

      swap = {
        chain_id:     context.chain_id,
        block_number: context.block_number,
        tx_hash:      tx_hash,
        log_index:    log_idx,
        pool_address: pool_addr,
        dex_name:     pool&.dex_name || DEX_NAME,
        sender:       sender,
        recipient:    recipient,
        token_in:     token_in,
        token_out:    token_out,
        amount_in:    amount_in.to_s,
        amount_out:   amount_out.to_s,
        price:        price&.to_f,
        sqrt_price_x96: nil,
        tick:         nil,
        created_at:   context.now,
        updated_at:   context.now
      }

      # Store in context for batch insert (not in transfers — separate table)
      context.swaps << swap
    end

    # Query token0() and token1() from V2 pair contract to auto-register pool
    def self.auto_register_v2_pool(chain_id, pool_address)
      rpc = EthereumRpc.new(chain_id: chain_id)

      # token0(): 0x0dfe1681, token1(): 0xd21220a7, symbol(): 0x95d89b41
      results = rpc.batch_call([
        { method: 'eth_call', params: [{ to: pool_address, data: '0x0dfe1681' }, 'latest'] },
        { method: 'eth_call', params: [{ to: pool_address, data: '0xd21220a7' }, 'latest'] }
      ])

      return nil unless results&.size == 2
      token0_raw = results[0]
      token1_raw = results[1]
      return nil unless token0_raw.is_a?(String) && token0_raw.length >= 66
      return nil unless token1_raw.is_a?(String) && token1_raw.length >= 66

      token0 = "0x#{token0_raw[-40..]}".downcase
      token1 = "0x#{token1_raw[-40..]}".downcase

      # Fetch symbols for both tokens
      sym0, sym1 = fetch_token_symbols(rpc, token0, token1)

      pool = DexPool.create!(
        chain_id: chain_id,
        pool_address: pool_address,
        dex_name: DEX_NAME,
        token0_address: token0,
        token1_address: token1,
        token0_symbol: sym0,
        token1_symbol: sym1
      )

      Rails.logger.info("Auto-registered V2 pool: #{pool_address} (#{sym0 || token0}/#{sym1 || token1})")
      pool
    rescue StandardError => e
      Rails.logger.debug("Failed to auto-register V2 pool #{pool_address}: #{e.message}")
      nil
    end

    # Fetch ERC-20 symbol() for two token addresses
    def self.fetch_token_symbols(rpc, token0, token1)
      results = rpc.batch_call([
        { method: 'eth_call', params: [{ to: token0, data: '0x95d89b41' }, 'latest'] },
        { method: 'eth_call', params: [{ to: token1, data: '0x95d89b41' }, 'latest'] }
      ])
      [decode_string_result(results&.dig(0)), decode_string_result(results&.dig(1))]
    rescue StandardError
      [nil, nil]
    end

    # Decode ABI-encoded string return value
    def self.decode_string_result(hex)
      return nil unless hex.is_a?(String) && hex.length > 2
      raw = [hex.sub(/\A0x/, '')].pack('H*')
      return nil if raw.length < 64

      offset = raw[0, 32].unpack1('H*').to_i(16)
      return nil if offset + 32 > raw.length

      len = raw[offset, 32].unpack1('H*').to_i(16)
      return nil if len == 0 || len > 100 || offset + 32 + len > raw.length

      result = raw[offset + 32, len].force_encoding('UTF-8')
      result.valid_encoding? ? result : nil
    rescue StandardError
      nil
    end
  end
end

TransferDecoder.register_log_decoder(
  Decoders::UniswapV2SwapDecoder::TOPIC0,
  Decoders::UniswapV2SwapDecoder
)
