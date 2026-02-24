# frozen_string_literal: true

class ChainConfig < ApplicationRecord
  has_one :indexer_cursor, primary_key: :chain_id, foreign_key: :chain_id

  NETWORK_TYPES = %w[mainnet testnet devnet].freeze
  CHAIN_TYPES = %w[evm utxo substrate].freeze

  # In-memory cache (11 chains max, refreshes every 60s)
  CACHE_TTL = 60

  def self.cached_all
    if @cache_expires_at.nil? || @cache_expires_at < Time.current
      @cached_configs = all.index_by(&:chain_id)
      @cache_expires_at = Time.current + CACHE_TTL
    end
    @cached_configs
  end

  def self.cached_find(chain_id)
    cached_all[chain_id.to_i]
  end

  def self.invalidate_cache!
    @cache_expires_at = nil
    @cached_configs = nil
  end

  after_commit :invalidate_cache
  def invalidate_cache
    self.class.invalidate_cache!
  end

  validates :chain_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :rpc_url, presence: true, if: -> { evm? && rpc_endpoints.blank? }
  validates :sidecar_url, presence: true, if: -> { substrate? }
  validates :network_type, inclusion: { in: NETWORK_TYPES }
  validates :chain_type, inclusion: { in: CHAIN_TYPES }
  validates :poll_interval_seconds, numericality: { greater_than: 0 }
  validates :blocks_per_batch, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :trace_method, inclusion: { in: %w[debug_traceBlock trace_block], allow_blank: true }

  scope :mainnet, -> { where(network_type: "mainnet") }
  scope :testnet, -> { where(network_type: "testnet") }
  scope :enabled, -> { where(enabled: true) }

  # Get ordered list of RPC URLs (primary rpc_url + rpc_endpoints sorted by priority)
  def rpc_url_list
    urls = []
    # rpc_endpoints sorted by priority (lower = higher priority)
    endpoints = (rpc_endpoints || []).sort_by { |e| e["priority"] || 99 }
    endpoints.each { |e| urls << e["url"] if e["url"].present? }
    # Legacy rpc_url as fallback if not already included
    urls << rpc_url if rpc_url.present? && !urls.include?(rpc_url)
    urls.uniq
  end

  # Get the active RPC URL (first in list)
  def active_rpc_url
    rpc_url_list.first || rpc_url
  end

  # Task queue for this chain — isolates chains from each other
  def task_queue
    base = ENV.fetch('TEMPORAL_TASK_QUEUE', 'evm-indexer')
    "#{base}-chain-#{chain_id}"
  end

  def status
    indexer_cursor&.status || "not_initialized"
  end

  def last_indexed_block
    indexer_cursor&.last_indexed_block || 0
  end

  # Default chain configs with public RPCs
  DEFAULTS = {
    # EVM chains
    1 => { name: "Ethereum", rpc_url: "https://eth.llamarpc.com", explorer_url: "https://etherscan.io", native_currency: "ETH", block_time_ms: 12_000, network_type: "mainnet", chain_type: "evm" },
    10 => { name: "Optimism", rpc_url: "https://mainnet.optimism.io", explorer_url: "https://optimistic.etherscan.io", native_currency: "ETH", block_time_ms: 2000, network_type: "mainnet", chain_type: "evm" },
    137 => { name: "Polygon", rpc_url: "https://polygon-bor-rpc.publicnode.com", explorer_url: "https://polygonscan.com", native_currency: "MATIC", block_time_ms: 2000, network_type: "mainnet", chain_type: "evm" },
    8453 => { name: "Base", rpc_url: "https://mainnet.base.org", explorer_url: "https://basescan.org", native_currency: "ETH", block_time_ms: 2000, network_type: "mainnet", chain_type: "evm" },
    42161 => { name: "Arbitrum", rpc_url: "https://arb1.arbitrum.io/rpc", explorer_url: "https://arbiscan.io", native_currency: "ETH", block_time_ms: 250, network_type: "mainnet", chain_type: "evm" },
    11155111 => { name: "Sepolia", rpc_url: "https://ethereum-sepolia-rpc.publicnode.com", explorer_url: "https://sepolia.etherscan.io", native_currency: "ETH", block_time_ms: 12_000, network_type: "testnet", chain_type: "evm" },
    # UTXO chains — use chain_id as BIP44 coin_type convention (non-EVM)
    # These need RPC endpoints configured manually (self-hosted node or provider)
    800_000_000 => { name: "Bitcoin", rpc_url: nil, explorer_url: "https://mempool.space", native_currency: "BTC", block_time_ms: 600_000, network_type: "mainnet", chain_type: "utxo", enabled: false, poll_interval_seconds: 30, blocks_per_batch: 1, confirmation_blocks: 6 },
    800_000_002 => { name: "Litecoin", rpc_url: nil, explorer_url: "https://litecoinspace.org", native_currency: "LTC", block_time_ms: 150_000, network_type: "mainnet", chain_type: "utxo", enabled: false, poll_interval_seconds: 15, blocks_per_batch: 5, confirmation_blocks: 6 },
    800_000_003 => { name: "Dogecoin", rpc_url: nil, explorer_url: "https://dogechain.info", native_currency: "DOGE", block_time_ms: 60_000, network_type: "mainnet", chain_type: "utxo", enabled: false, poll_interval_seconds: 10, blocks_per_batch: 5, confirmation_blocks: 6 },
    800_000_145 => { name: "Bitcoin Cash", rpc_url: nil, explorer_url: "https://blockchair.com/bitcoin-cash", native_currency: "BCH", block_time_ms: 600_000, network_type: "mainnet", chain_type: "utxo", enabled: false, poll_interval_seconds: 30, blocks_per_batch: 1, confirmation_blocks: 6 },
    # Substrate chains — use 900_000_xxx namespace
    900_000_001 => { name: "Polkadot Asset Hub", rpc_url: "https://polkadot-asset-hub-rpc.polkadot.io", sidecar_url: "https://polkadot-asset-hub-public-sidecar.parity-chains.parity.io", explorer_url: "https://assethub-polkadot.subscan.io", native_currency: "DOT", block_time_ms: 12_000, network_type: "mainnet", chain_type: "substrate", enabled: false, poll_interval_seconds: 6, blocks_per_batch: 10 }
  }.freeze

  def evm?
    chain_type == 'evm'
  end

  def utxo?
    chain_type == 'utxo'
  end

  def substrate?
    chain_type == 'substrate'
  end
end
