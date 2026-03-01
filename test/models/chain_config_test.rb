# frozen_string_literal: true

require 'test_helper'

class ChainConfigTest < ActiveSupport::TestCase
  setup do
    ChainConfig.invalidate_cache!
  end

  test 'cached_find returns correct chain' do
    chain = create_chain_config(chain_id: 1, name: 'Ethereum')
    found = ChainConfig.cached_find(1)
    assert_equal 'Ethereum', found.name
  end

  test 'cached_find returns nil for missing chain' do
    assert_nil ChainConfig.cached_find(999_999)
  end

  test 'cache expires after TTL' do
    create_chain_config(chain_id: 42, name: 'TestChain')
    ChainConfig.cached_find(42)

    # Simulate cache expiry
    ChainConfig.instance_variable_set(:@cache_expires_at, Time.current - 1)
    found = ChainConfig.cached_find(42)
    assert_equal 'TestChain', found.name
  end

  test 'rpc_endpoints JSON handling' do
    chain = ChainConfig.create!(
      chain_id: 77777,
      name: 'TestRPC',
      rpc_url: 'https://fallback.rpc',
      network_type: 'mainnet',
      chain_type: 'evm',
      poll_interval_seconds: 2,
      blocks_per_batch: 10,
      rpc_endpoints: [
        { 'url' => 'https://primary.rpc', 'priority' => 1 },
        { 'url' => 'https://secondary.rpc', 'priority' => 2 }
      ]
    )

    assert_equal 'https://primary.rpc', chain.active_rpc_url
    assert_equal ['https://primary.rpc', 'https://secondary.rpc', 'https://fallback.rpc'], chain.rpc_url_list
  end

  test 'task_queue includes chain_id' do
    chain = create_chain_config(chain_id: 137, name: 'Polygon')
    assert_match(/chain-137$/, chain.task_queue)
  end

  test 'validates required fields' do
    chain = ChainConfig.new
    assert_not chain.valid?
    assert_includes chain.errors[:chain_id], "can't be blank"
    assert_includes chain.errors[:name], "can't be blank"
  end

  test 'validates chain_type inclusion' do
    chain = ChainConfig.new(chain_id: 999, name: 'Test', rpc_url: 'http://x', chain_type: 'invalid', network_type: 'mainnet')
    assert_not chain.valid?
    assert_includes chain.errors[:chain_type], 'is not included in the list'
  end

  test 'invalidate_cache! clears cache' do
    create_chain_config(chain_id: 1)
    ChainConfig.cached_find(1)
    ChainConfig.invalidate_cache!
    assert_nil ChainConfig.instance_variable_get(:@cached_configs)
  end

  # ── rpc_url_list priority sorting ──

  test 'rpc_url_list sorts by priority' do
    chain = ChainConfig.create!(
      chain_id: 77701,
      name: 'PriorityTest',
      rpc_url: 'https://fallback.rpc',
      network_type: 'mainnet',
      chain_type: 'evm',
      poll_interval_seconds: 2,
      blocks_per_batch: 10,
      rpc_endpoints: [
        { 'url' => 'https://low-priority.rpc', 'priority' => 10 },
        { 'url' => 'https://high-priority.rpc', 'priority' => 1 }
      ]
    )

    urls = chain.rpc_url_list
    assert_equal 'https://high-priority.rpc', urls[0]
    assert_equal 'https://low-priority.rpc', urls[1]
    assert_equal 'https://fallback.rpc', urls[2]
  end

  test 'rpc_url_list deduplicates' do
    chain = ChainConfig.create!(
      chain_id: 77702,
      name: 'DedupTest',
      rpc_url: 'https://same.rpc',
      network_type: 'mainnet',
      chain_type: 'evm',
      poll_interval_seconds: 2,
      blocks_per_batch: 10,
      rpc_endpoints: [{ 'url' => 'https://same.rpc', 'priority' => 1 }]
    )

    assert_equal ['https://same.rpc'], chain.rpc_url_list
  end

  test 'rpc_url_list with no endpoints returns rpc_url' do
    chain = create_chain_config(chain_id: 77703, rpc_url: 'https://solo.rpc')
    assert_equal ['https://solo.rpc'], chain.rpc_url_list
  end

  # ── active_rpc_url ──

  test 'active_rpc_url returns first from list' do
    chain = ChainConfig.create!(
      chain_id: 77704,
      name: 'ActiveTest',
      rpc_url: 'https://fallback.rpc',
      network_type: 'mainnet',
      chain_type: 'evm',
      poll_interval_seconds: 2,
      blocks_per_batch: 10,
      rpc_endpoints: [{ 'url' => 'https://primary.rpc', 'priority' => 1 }]
    )
    assert_equal 'https://primary.rpc', chain.active_rpc_url
  end

  # ── chain type predicates ──

  test 'evm? returns true for evm chains' do
    chain = create_chain_config(chain_id: 77705, chain_type: 'evm')
    assert chain.evm?
    assert_not chain.utxo?
    assert_not chain.substrate?
  end

  test 'utxo? returns true for utxo chains' do
    chain = ChainConfig.create!(
      chain_id: 77706, name: 'BTC', rpc_url: 'https://btc.rpc',
      network_type: 'mainnet', chain_type: 'utxo',
      poll_interval_seconds: 30, blocks_per_batch: 1
    )
    assert chain.utxo?
    assert_not chain.evm?
  end

  test 'substrate? returns true for substrate chains' do
    chain = ChainConfig.create!(
      chain_id: 77707, name: 'DOT', rpc_url: 'https://dot.rpc',
      sidecar_url: 'https://sidecar.dot',
      network_type: 'mainnet', chain_type: 'substrate',
      poll_interval_seconds: 6, blocks_per_batch: 10
    )
    assert chain.substrate?
  end

  # ── catchup_parallel_batches validation ──

  test 'catchup_parallel_batches must be 1-10' do
    chain = ChainConfig.new(
      chain_id: 77708, name: 'Test', rpc_url: 'http://x',
      chain_type: 'evm', network_type: 'mainnet',
      poll_interval_seconds: 2, blocks_per_batch: 10,
      catchup_parallel_batches: 0
    )
    assert_not chain.valid?

    chain.catchup_parallel_batches = 11
    assert_not chain.valid?

    chain.catchup_parallel_batches = 5
    assert chain.valid?
  end

  # ── DEFAULTS ──

  test 'DEFAULTS contains expected chains' do
    assert ChainConfig::DEFAULTS.key?(1), 'should have Ethereum'
    assert ChainConfig::DEFAULTS.key?(137), 'should have Polygon'
    assert ChainConfig::DEFAULTS.key?(42161), 'should have Arbitrum'
    assert ChainConfig::DEFAULTS.key?(800_000_000), 'should have Bitcoin'
    assert ChainConfig::DEFAULTS.key?(900_000_001), 'should have Polkadot Asset Hub'
  end

  test 'DEFAULTS all have required fields' do
    ChainConfig::DEFAULTS.each do |chain_id, config|
      assert config[:name].present?, "chain #{chain_id} missing name"
      assert config[:network_type].present?, "chain #{chain_id} missing network_type"
      assert config[:chain_type].present?, "chain #{chain_id} missing chain_type"
    end
  end
end
