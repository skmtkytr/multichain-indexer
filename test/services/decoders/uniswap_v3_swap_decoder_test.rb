# frozen_string_literal: true

require 'test_helper'

class UniswapV3SwapDecoderTest < ActiveSupport::TestCase
  setup do
    @chain_id = 1
    @pool_addr = '0x' + '33' * 20
    @token0 = '0x' + 'aa' * 20
    @token1 = '0x' + 'bb' * 20

    create_chain_config(chain_id: @chain_id)
    create_dex_pool(
      chain_id: @chain_id,
      pool_address: @pool_addr,
      dex_name: 'uniswap_v3',
      token0_address: @token0,
      token1_address: @token1,
      fee_tier: 3000
    )
    DexPool.invalidate_cache!
  end

  def encode_int256(val)
    if val < 0
      ((1 << 256) + val).to_s(16).rjust(64, '0')
    else
      val.to_s(16).rjust(64, '0')
    end
  end

  test 'decodes V3 swap with token0 in, token1 out' do
    amount0 = 1_000_000_000_000_000_000  # positive = token0 enters pool
    amount1 = -2_000_000_000             # negative = token1 leaves pool
    sqrt_price = 79228162514264337593543950336 # ~1.0
    liquidity = 1_000_000
    tick = -100

    data = '0x' +
      encode_int256(amount0) +
      encode_int256(amount1) +
      sqrt_price.to_s(16).rjust(64, '0') +
      liquidity.to_s(16).rjust(64, '0') +
      encode_int256(tick)

    log = {
      'topics' => [
        Decoders::UniswapV3SwapDecoder::TOPIC0,
        '0x' + '0' * 24 + 'cc' * 20,
        '0x' + '0' * 24 + 'dd' * 20
      ],
      'data' => data,
      'address' => @pool_addr,
      'logIndex' => '0x5',
      'transactionHash' => '0x' + 'ee' * 32
    }

    context = TransferDecoder::DecoderContext.new(chain_id: @chain_id, block_number: 200, now: Time.current)
    Decoders::UniswapV3SwapDecoder.decode_log(context, log, [])

    assert_equal 1, context.swaps.size
    swap = context.swaps.first
    assert_equal @token0, swap[:token_in]
    assert_equal @token1, swap[:token_out]
    assert_equal amount0.to_s, swap[:amount_in]
    assert_equal amount1.abs.to_s, swap[:amount_out]
    assert_equal sqrt_price.to_s, swap[:sqrt_price_x96]
    assert_equal(-100, swap[:tick])
    assert_equal 'uniswap_v3', swap[:dex_name]
  end

  test 'decodes V3 swap with token1 in, token0 out' do
    amount0 = -500_000  # token0 leaves pool
    amount1 = 1_000_000 # token1 enters pool
    sqrt_price = 79228162514264337593543950336
    liquidity = 500_000
    tick = 42

    data = '0x' +
      encode_int256(amount0) +
      encode_int256(amount1) +
      sqrt_price.to_s(16).rjust(64, '0') +
      liquidity.to_s(16).rjust(64, '0') +
      encode_int256(tick)

    log = {
      'topics' => [
        Decoders::UniswapV3SwapDecoder::TOPIC0,
        '0x' + '0' * 24 + 'cc' * 20,
        '0x' + '0' * 24 + 'dd' * 20
      ],
      'data' => data,
      'address' => @pool_addr,
      'logIndex' => '0x0',
      'transactionHash' => '0x' + 'ff' * 32
    }

    context = TransferDecoder::DecoderContext.new(chain_id: @chain_id, block_number: 200, now: Time.current)
    Decoders::UniswapV3SwapDecoder.decode_log(context, log, [])

    swap = context.swaps.first
    assert_equal @token1, swap[:token_in]
    assert_equal @token0, swap[:token_out]
    assert_equal 42, swap[:tick]
  end

  test 'decode_int256 handles negative values' do
    assert_equal(-1, Decoders::UniswapV3SwapDecoder.decode_int256('f' * 64))
    assert_equal 1, Decoders::UniswapV3SwapDecoder.decode_int256('0' * 63 + '1')
    assert_equal 0, Decoders::UniswapV3SwapDecoder.decode_int256('0' * 64)
  end
end
