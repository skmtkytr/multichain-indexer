# frozen_string_literal: true

require 'test_helper'

class UniswapV2SwapDecoderTest < ActiveSupport::TestCase
  setup do
    @chain_id = 1
    @pool_addr = '0x' + '11' * 20
    @token0 = '0x' + 'aa' * 20
    @token1 = '0x' + 'bb' * 20

    create_chain_config(chain_id: @chain_id)
    create_dex_pool(
      chain_id: @chain_id,
      pool_address: @pool_addr,
      dex_name: 'uniswap_v2',
      token0_address: @token0,
      token1_address: @token1
    )
    DexPool.invalidate_cache!
  end

  test 'decodes V2 swap with amount0In and amount1Out' do
    amount0_in = 1_000_000_000_000_000_000 # 1 ETH
    amount1_out = 2000_000_000 # 2000 USDC (6 decimals)

    data = '0x' +
      amount0_in.to_s(16).rjust(64, '0') +
      (0).to_s(16).rjust(64, '0') +
      (0).to_s(16).rjust(64, '0') +
      amount1_out.to_s(16).rjust(64, '0')

    log = {
      'topics' => [
        Decoders::UniswapV2SwapDecoder::TOPIC0,
        '0x' + '0' * 24 + 'cc' * 20, # sender
        '0x' + '0' * 24 + 'dd' * 20  # to
      ],
      'data' => data,
      'address' => @pool_addr,
      'logIndex' => '0xa',
      'transactionHash' => '0x' + 'ee' * 32
    }

    context = TransferDecoder::DecoderContext.new(chain_id: @chain_id, block_number: 100, now: Time.current)
    transfers = []
    Decoders::UniswapV2SwapDecoder.decode_log(context, log, transfers)

    assert_equal 0, transfers.size # swaps go to context.swaps, not transfers
    assert_equal 1, context.swaps.size

    swap = context.swaps.first
    assert_equal @token0, swap[:token_in]
    assert_equal @token1, swap[:token_out]
    assert_equal amount0_in.to_s, swap[:amount_in]
    assert_equal amount1_out.to_s, swap[:amount_out]
    assert_equal 'uniswap_v2', swap[:dex_name]
  end

  test 'calculates price ratio' do
    amount0_in = 1_000
    amount1_out = 2_000

    data = '0x' +
      amount0_in.to_s(16).rjust(64, '0') +
      (0).to_s(16).rjust(64, '0') +
      (0).to_s(16).rjust(64, '0') +
      amount1_out.to_s(16).rjust(64, '0')

    log = {
      'topics' => [
        Decoders::UniswapV2SwapDecoder::TOPIC0,
        '0x' + '0' * 24 + 'cc' * 20,
        '0x' + '0' * 24 + 'dd' * 20
      ],
      'data' => data,
      'address' => @pool_addr,
      'logIndex' => '0x0',
      'transactionHash' => '0x' + 'ff' * 32
    }

    context = TransferDecoder::DecoderContext.new(chain_id: @chain_id, block_number: 100, now: Time.current)
    Decoders::UniswapV2SwapDecoder.decode_log(context, log, [])

    assert_in_delta 2.0, context.swaps.first[:price], 0.001
  end

  test 'handles unknown pool gracefully when auto-register fails' do
    unknown_pool = '0x' + '99' * 20
    DexPool.invalidate_cache!

    # Patch auto_register to return nil (simulating RPC failure)
    original = Decoders::UniswapV2SwapDecoder.method(:auto_register_v2_pool)
    Decoders::UniswapV2SwapDecoder.define_singleton_method(:auto_register_v2_pool) { |_chain_id, _addr| nil }

    data = '0x' +
      (1000).to_s(16).rjust(64, '0') +
      (0).to_s(16).rjust(64, '0') +
      (0).to_s(16).rjust(64, '0') +
      (2000).to_s(16).rjust(64, '0')

    log = {
      'topics' => [
        Decoders::UniswapV2SwapDecoder::TOPIC0,
        '0x' + '0' * 24 + 'cc' * 20,
        '0x' + '0' * 24 + 'dd' * 20
      ],
      'data' => data,
      'address' => unknown_pool,
      'logIndex' => '0x0',
      'transactionHash' => '0x' + 'ab' * 32
    }

    context = TransferDecoder::DecoderContext.new(chain_id: @chain_id, block_number: 100, now: Time.current)
    Decoders::UniswapV2SwapDecoder.decode_log(context, log, [])

    assert_equal 1, context.swaps.size
    assert_nil context.swaps.first[:token_in]
  ensure
    Decoders::UniswapV2SwapDecoder.define_singleton_method(:auto_register_v2_pool, original)
  end
end
