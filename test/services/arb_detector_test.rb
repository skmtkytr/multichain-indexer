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

    create_chain_config(chain_id: @chain_id)

    # Clear ArbDetector's internal decimals cache between tests
    ArbDetector.send(:clear_decimals_cache!)

    # Default: create tokens with 18 decimals so existing tests keep working
    TokenContract.find_or_create_by!(address: @token_a, chain_id: @chain_id) do |t|
      t.decimals = 18
      t.standard = 'erc20'
    end
    TokenContract.find_or_create_by!(address: @token_b, chain_id: @chain_id) do |t|
      t.decimals = 18
      t.standard = 'erc20'
    end
  end

  # ====================================================
  # Original tests (unchanged logic, still pass)
  # ====================================================

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

    TokenContract.find_or_create_by!(address: token_c, chain_id: @chain_id) do |t|
      t.decimals = 18
      t.standard = 'erc20'
    end

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

  # ====================================================
  # Decimal normalization tests
  # ====================================================

  test 'normalized_price computes correctly for same decimals' do
    # 1000 tokens in (18 dec), 2000 tokens out (18 dec) → price = 2.0
    price = ArbDetector.normalized_price(
      '1000000000000000000000',  # 1000 * 10^18
      '2000000000000000000000',  # 2000 * 10^18
      18, 18
    )
    assert_in_delta 2.0, price.to_f, 0.0001
  end

  test 'normalized_price computes correctly for 18 vs 6 decimals (WETH/USDT)' do
    # 1 WETH (18 dec) for 3000 USDT (6 dec)
    amount_in  = (BigDecimal('1') * BigDecimal(10)**18).to_i.to_s    # 1e18
    amount_out = (BigDecimal('3000') * BigDecimal(10)**6).to_i.to_s  # 3000e6

    price = ArbDetector.normalized_price(amount_in, amount_out, 18, 6)
    assert_in_delta 3000.0, price.to_f, 0.0001
  end

  test 'normalized_price computes correctly for 8 vs 6 decimals (WBTC/USDC)' do
    # 1 WBTC (8 dec) for 60000 USDC (6 dec)
    amount_in  = (BigDecimal('1') * BigDecimal(10)**8).to_i.to_s
    amount_out = (BigDecimal('60000') * BigDecimal(10)**6).to_i.to_s

    price = ArbDetector.normalized_price(amount_in, amount_out, 8, 6)
    assert_in_delta 60000.0, price.to_f, 0.001
  end

  test 'normalized_price returns nil when amount_in is zero' do
    price = ArbDetector.normalized_price('0', '1000000', 18, 6)
    assert_nil price
  end

  test 'normalized_price returns nil when amount_out is zero' do
    price = ArbDetector.normalized_price('1000000', '0', 18, 6)
    assert_nil price
  end

  # ====================================================
  # Decimal-corrected arb detection (18 dec vs 6 dec)
  # ====================================================

  test 'correct spread with different decimals (WETH 18 / USDT 6)' do
    weth = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
    usdt = '0xdac17f958d2ee523a2206206994597c13d831ec7'

    TokenContract.find_or_create_by!(address: weth, chain_id: @chain_id) do |t|
      t.decimals = 18; t.symbol = 'WETH'; t.standard = 'erc20'
    end
    TokenContract.find_or_create_by!(address: usdt, chain_id: @chain_id) do |t|
      t.decimals = 6; t.symbol = 'USDT'; t.standard = 'erc20'
    end

    # Pool1: 1 WETH → 3000 USDT (price = 3000)
    # Pool2: 1 WETH → 3030 USDT (price = 3030)
    # Spread = (3030-3000)/3015 * 10000 ≈ 99.5 bps
    one_weth = (BigDecimal(10)**18).to_i.to_s
    usdt_3000 = (BigDecimal('3000') * BigDecimal(10)**6).to_i.to_s
    usdt_3030 = (BigDecimal('3030') * BigDecimal(10)**6).to_i.to_s

    # Sorted pair: usdt < weth lexicographically
    pair = [weth, usdt].sort

    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xa1', log_index: 0,
        pool_address: @pool1, dex_name: 'uniswap_v2', token_in: weth, token_out: usdt,
        amount_in: one_weth, amount_out: usdt_3000, sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xa2', log_index: 1,
        pool_address: @pool2, dex_name: 'sushiswap', token_in: weth, token_out: usdt,
        amount_in: one_weth, amount_out: usdt_3030, sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 1, opps.size

    opp = opps.first
    # Spread should be ~99.5 bps, NOT the absurd 20000 bps from raw comparison
    assert_in_delta 99.5, opp[:spread_bps], 1.0
    assert opp[:spread_bps] < 200, "Spread should be reasonable, not inflated"

    # price_buy and price_sell should be human-readable normalized prices
    assert_in_delta 3000.0, [opp[:price_buy], opp[:price_sell]].min, 1.0
    assert_in_delta 3030.0, [opp[:price_buy], opp[:price_sell]].max, 1.0
  end

  test 'price_buy < price_sell always holds' do
    weth = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
    usdt = '0xdac17f958d2ee523a2206206994597c13d831ec7'

    TokenContract.find_or_create_by!(address: weth, chain_id: @chain_id) do |t|
      t.decimals = 18; t.symbol = 'WETH'; t.standard = 'erc20'
    end
    TokenContract.find_or_create_by!(address: usdt, chain_id: @chain_id) do |t|
      t.decimals = 6; t.symbol = 'USDT'; t.standard = 'erc20'
    end

    one_weth = (BigDecimal(10)**18).to_i.to_s
    usdt_low  = (BigDecimal('2950') * BigDecimal(10)**6).to_i.to_s
    usdt_high = (BigDecimal('3050') * BigDecimal(10)**6).to_i.to_s

    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xb1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: weth, token_out: usdt,
        amount_in: one_weth, amount_out: usdt_low, sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xb2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: weth, token_out: usdt,
        amount_in: one_weth, amount_out: usdt_high, sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 1, opps.size
    assert opps.first[:price_buy] < opps.first[:price_sell]
  end

  # ====================================================
  # Decimals unknown → skip (false positive prevention)
  # ====================================================

  test 'skips pair when token decimals are unknown' do
    unknown_token = '0x' + 'dd' * 20
    # Create token WITHOUT decimals
    TokenContract.find_or_create_by!(address: unknown_token, chain_id: @chain_id) do |t|
      t.decimals = nil; t.standard = 'erc20'
    end

    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xc1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: unknown_token,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xc2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: unknown_token,
        amount_in: '1000', amount_out: '3000', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 0, opps.size
  end

  test 'skips pair when token has no TokenContract record at all' do
    nonexistent = '0x' + 'ef' * 20
    # Don't create any TokenContract record

    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xd1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: nonexistent,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xd2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: nonexistent,
        amount_in: '1000', amount_out: '3000', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 0, opps.size
  end

  # ====================================================
  # Edge cases
  # ====================================================

  test 'handles amount_in of zero gracefully' do
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xe1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: @token_b,
        amount_in: '0', amount_out: '2000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xe2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' }
    ]

    # Should not raise, just skip the zero-amount swap
    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 0, opps.size  # only 1 valid swap per pool, need 2 pools
  end

  test 'handles amount_out of zero gracefully' do
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xf1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '0', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xf2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 0, opps.size
  end

  test 'handles very large amounts (whale trades)' do
    # 10,000 WETH worth ~$30M each side
    large_in  = (BigDecimal('10000') * BigDecimal(10)**18).to_i.to_s
    large_out1 = (BigDecimal('30000000') * BigDecimal(10)**18).to_i.to_s  # 30M
    large_out2 = (BigDecimal('30300000') * BigDecimal(10)**18).to_i.to_s  # 30.3M

    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xg1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: @token_b,
        amount_in: large_in, amount_out: large_out1, sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xg2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: @token_b,
        amount_in: large_in, amount_out: large_out2, sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 1, opps.size
    assert_in_delta 99.5, opps.first[:spread_bps], 1.0
  end

  test 'handles very small amounts (dust trades)' do
    # 1 wei in, 2 wei out vs 1 wei in, 3 wei out — same decimals
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xh1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: @token_b,
        amount_in: '1', amount_out: '2', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xh2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: @token_b,
        amount_in: '1', amount_out: '3', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 1, opps.size
    assert opps.first[:spread_bps] > 0
  end

  test 'spread_bps accuracy for known values' do
    # Pool1: price = 2.0, Pool2: price = 2.1
    # mid = 2.05, spread = 0.1/2.05 * 10000 ≈ 487.8 bps
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xi1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2000', sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xi2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: @token_b,
        amount_in: '1000', amount_out: '2100', sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 1, opps.size
    expected_bps = (0.1 / 2.05 * 10_000).round(2)
    assert_in_delta expected_bps, opps.first[:spread_bps], 0.1
  end

  test 'same decimals pair produces identical results to pre-normalization behavior' do
    # Both 18 decimals → normalization divides both sides by 10^18, ratio unchanged
    swaps = [
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xj1', log_index: 0,
        pool_address: @pool1, dex_name: 'v2', token_in: @token_a, token_out: @token_b,
        amount_in: '5000000000000000000', amount_out: '10000000000000000000',
        sender: '0x1', recipient: '0x1' },
      { chain_id: @chain_id, block_number: @block, tx_hash: '0xj2', log_index: 1,
        pool_address: @pool2, dex_name: 'v3', token_in: @token_a, token_out: @token_b,
        amount_in: '5000000000000000000', amount_out: '11000000000000000000',
        sender: '0x1', recipient: '0x1' }
    ]

    opps = ArbDetector.analyze_swaps(chain_id: @chain_id, block_number: @block, swaps: swaps)
    assert_equal 1, opps.size
    # price_buy = 2.0, price_sell = 2.2
    assert_in_delta 2.0, opp_min_price(opps.first), 0.001
    assert_in_delta 2.2, opp_max_price(opps.first), 0.001
  end

  private

  def opp_min_price(opp)
    [opp[:price_buy], opp[:price_sell]].min
  end

  def opp_max_price(opp)
    [opp[:price_buy], opp[:price_sell]].max
  end
end
