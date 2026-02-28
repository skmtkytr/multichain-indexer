# frozen_string_literal: true

require 'test_helper'

class DexPoolTest < ActiveSupport::TestCase
  setup do
    DexPool.invalidate_cache!
    @pool = create_dex_pool(
      chain_id: 1,
      pool_address: '0x' + 'ab' * 20,
      token0_address: '0x' + 'aa' * 20,
      token1_address: '0x' + 'bb' * 20
    )
  end

  test 'cached_find returns pool' do
    found = DexPool.cached_find(1, '0x' + 'ab' * 20)
    assert_equal @pool.id, found.id
  end

  test 'cached_find returns nil for missing pool' do
    assert_nil DexPool.cached_find(1, '0x' + '99' * 20)
  end

  test 'cached_find uses cache on second call' do
    DexPool.cached_find(1, @pool.pool_address)
    # Delete from DB; cache should still work
    @pool.delete
    found = DexPool.cached_find(1, @pool.pool_address)
    assert_not_nil found
  end

  test 'uniqueness constraint on chain_id + pool_address' do
    dup = DexPool.new(
      chain_id: 1,
      pool_address: @pool.pool_address,
      dex_name: 'sushiswap',
      token0_address: '0x' + 'cc' * 20,
      token1_address: '0x' + 'dd' * 20
    )
    assert_not dup.valid?
    assert_includes dup.errors[:pool_address], 'has already been taken'
  end

  test 'other_token returns the opposite token' do
    assert_equal @pool.token1_address, @pool.other_token(@pool.token0_address)
    assert_equal @pool.token0_address, @pool.other_token(@pool.token1_address)
  end

  test 'has_token? works' do
    assert @pool.has_token?(@pool.token0_address)
    assert @pool.has_token?(@pool.token1_address)
    assert_not @pool.has_token?('0x' + 'ff' * 20)
  end

  test 'invalidate_cache! clears all entries' do
    DexPool.cached_find(1, @pool.pool_address)
    DexPool.invalidate_cache!
    # After invalidation, should re-query DB
    @pool.delete
    assert_nil DexPool.cached_find(1, @pool.pool_address)
  end
end
