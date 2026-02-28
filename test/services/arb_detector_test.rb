# frozen_string_literal: true

require 'test_helper'

class ArbDetectorTest < ActiveSupport::TestCase
  setup do
    @chain_id = 1
    @block = 12345
    @token_a = '0x' + 'aa' * 20
    @token_b = '0x' + 'bb' * 20
    @pool1 = '0x' + '11' * 20
    @pool2 = '0x' + '22' * 20
  end

  test 'detects arbitrage with two swaps on different pools' do
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x1', log_index: 0,
        pool_address: @pool1, dex_name: 'uniswap_v2', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x2', log_index: 1,
        pool_address: @pool2, dex_name: 'sushiswap', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2200', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 1, opps.size
    assert opps.first[:spread_bps] > 5
    assert_equal 'direct', opps.first[:arb_type]
  end

  test 'no opportunity with same pool' do
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x1', log_index: 0,
        pool_address: @pool1, dex_name: 'uniswap_v2', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x2', log_index: 1,
        pool_address: @pool1, dex_name: 'uniswap_v2', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2200', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 0, opps.size
  end

  test 'no opportunity when spread below threshold' do
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x1', log_index: 0,
        pool_address: @pool1, dex_name: 'uniswap_v2', token_in: @token_a, token_out: @token_b,
        amount_in: '10000', amount_out: '20000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x2', log_index: 1,
        pool_address: @pool2, dex_name: 'sushiswap', token_in: @token_a, token_out: @token_b,
        amount_in: '10000', amount_out: '20001', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 0, opps.size
  end

  test 'detects multiple pairs in same block' do
    token_c = '0x' + 'cc' * 20
    pool3 = '0x' + '33' * 20

    swaps = [
      # Pair A/B
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2500', sender: '0x1', recipient: '0x1' },
      # Pair A/C
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x3', log_index: 2,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: token_c,
        amount_in: '1000', amount_out: '3000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x4', log_index: 3,
        pool_address: pool3, dex_name: 'v3', token_in: @token_a, token_out: token_c,
        amount_in: '1000', amount_out: '4000', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 2, opps.size
  end

  test 'returns empty for single swap' do
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0x1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 0, opps.size
  end
end
