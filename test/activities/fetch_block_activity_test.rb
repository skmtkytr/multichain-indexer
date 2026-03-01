# frozen_string_literal: true

require 'test_helper'
require 'ostruct'

class FetchBlockActivityTest < ActiveSupport::TestCase
  setup do
    @activity = Indexer::FetchBlockActivity.new
  end

  # ── get_latest action ──

  test 'get_latest returns block number' do
    rpc = Object.new
    rpc.define_singleton_method(:get_block_number) { |tag:| 42 }

    original_new = EthereumRpc.method(:new)
    EthereumRpc.define_singleton_method(:new) { |**| rpc }
    begin
      result = @activity.execute('action' => 'get_latest', 'chain_id' => 1)
      assert_equal 42, result
    ensure
      EthereumRpc.define_singleton_method(:new, original_new)
    end
  end

  test 'get_latest falls back to latest minus confirmations' do
    config = OpenStruct.new(block_tag: 'finalized', confirmation_blocks: 3, supports_block_receipts: true)

    rpc = Object.new
    rpc.define_singleton_method(:get_block_number) do |tag:|
      tag == 'finalized' ? nil : 100
    end

    original_find = ChainConfig.method(:find_by)
    original_new = EthereumRpc.method(:new)
    ChainConfig.define_singleton_method(:find_by) { |**| config }
    EthereumRpc.define_singleton_method(:new) { |**| rpc }
    begin
      result = @activity.execute('action' => 'get_latest', 'chain_id' => 1)
      assert_equal 97, result
    ensure
      ChainConfig.define_singleton_method(:find_by, original_find)
      EthereumRpc.define_singleton_method(:new, original_new)
    end
  end

  # ── fetch_full_block action ──

  test 'fetch_full_block returns data' do
    block_data = { 'number' => '0x10', 'transactions' => [] }
    rpc = Object.new
    rpc.define_singleton_method(:fetch_full_block) { |n, supports_block_receipts:| { 'block' => block_data } }

    original_new = EthereumRpc.method(:new)
    EthereumRpc.define_singleton_method(:new) { |**| rpc }
    begin
      result = @activity.execute('action' => 'fetch_full_block', 'chain_id' => 1, 'block_number' => 16)
      assert_equal block_data, result['block']
    ensure
      EthereumRpc.define_singleton_method(:new, original_new)
    end
  end

  test 'fetch_full_block returns nil when missing' do
    rpc = Object.new
    rpc.define_singleton_method(:fetch_full_block) { |*| nil }

    original_new = EthereumRpc.method(:new)
    EthereumRpc.define_singleton_method(:new) { |**| rpc }
    begin
      result = @activity.execute('action' => 'fetch_full_block', 'chain_id' => 1, 'block_number' => 999)
      assert_nil result
    ensure
      EthereumRpc.define_singleton_method(:new, original_new)
    end
  end

  # ── fetch_block action ──

  test 'fetch_block returns block with chain_id' do
    block = { 'number' => '0xa', 'transactions' => [] }
    rpc = Object.new
    rpc.define_singleton_method(:get_block_by_number) { |n, full_transactions:| block }

    original_new = EthereumRpc.method(:new)
    EthereumRpc.define_singleton_method(:new) { |**| rpc }
    begin
      result = @activity.execute('action' => 'fetch_block', 'chain_id' => 5, 'block_number' => 10)
      assert_equal 5, result['chain_id']
    ensure
      EthereumRpc.define_singleton_method(:new, original_new)
    end
  end

  # ── NonRetryableError wrapping ──

  test 'wraps non-retryable error' do
    rpc = Object.new
    rpc.define_singleton_method(:get_block_number) { |**| raise EthereumRpc::NonRetryableError, 'bad' }

    original_new = EthereumRpc.method(:new)
    EthereumRpc.define_singleton_method(:new) { |**| rpc }
    begin
      assert_raises(Temporalio::Error::ApplicationError) do
        @activity.execute('action' => 'get_latest', 'chain_id' => 1)
      end
    ensure
      EthereumRpc.define_singleton_method(:new, original_new)
    end
  end
end
