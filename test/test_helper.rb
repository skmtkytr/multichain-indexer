# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers (default: processors)
  # parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  self.use_transactional_tests = true

  # Helper to create a chain_config record
  def create_chain_config(attrs = {})
    defaults = {
      chain_id: attrs[:chain_id] || 1,
      name: 'Ethereum',
      rpc_url: 'https://eth.llamarpc.com',
      network_type: 'mainnet',
      chain_type: 'evm',
      enabled: true,
      poll_interval_seconds: 2,
      blocks_per_batch: 10,
      block_tag: 'finalized'
    }
    ChainConfig.find_or_create_by!(chain_id: defaults[:chain_id]) do |c|
      defaults.merge(attrs).each { |k, v| c.send(:"#{k}=", v) }
    end
  end

  # Helper to create an indexed block
  def create_indexed_block(attrs = {})
    defaults = {
      number: attrs[:number] || 100,
      block_hash: "0x#{'ab' * 32}",
      parent_hash: "0x#{'cd' * 32}",
      timestamp: Time.current.to_i,
      chain_id: 1,
      transaction_count: 0
    }
    IndexedBlock.create!(defaults.merge(attrs))
  end

  # Helper to create an asset transfer
  def create_asset_transfer(attrs = {})
    defaults = {
      tx_hash: "0x#{'ee' * 32}",
      block_number: 100,
      chain_id: 1,
      transfer_type: 'native',
      from_address: "0x#{'aa' * 20}",
      to_address: "0x#{'bb' * 20}",
      amount: 1_000_000_000_000_000_000,
      log_index: attrs[:log_index] || -1,
      trace_index: attrs[:trace_index] || -1
    }
    AssetTransfer.create!(defaults.merge(attrs))
  end

  # Helper to create address subscription
  def create_subscription(attrs = {})
    defaults = {
      address: "0x#{'aa' * 20}",
      webhook_url: 'https://example.com/webhook',
      direction: 'both',
      enabled: true
    }
    AddressSubscription.create!(defaults.merge(attrs))
  end

  # Helper to create a DexPool
  def create_dex_pool(attrs = {})
    defaults = {
      chain_id: 1,
      pool_address: "0x#{'11' * 20}",
      dex_name: 'uniswap_v2',
      token0_address: "0x#{'aa' * 20}",
      token1_address: "0x#{'bb' * 20}"
    }
    DexPool.create!(defaults.merge(attrs))
  end
end
