class ChainConfig < ApplicationRecord
  has_one :indexer_cursor, primary_key: :chain_id, foreign_key: :chain_id

  NETWORK_TYPES = %w[mainnet testnet devnet].freeze

  validates :chain_id, presence: true, uniqueness: true
  validates :name, :rpc_url, presence: true
  validates :network_type, inclusion: { in: NETWORK_TYPES }
  validates :poll_interval_seconds, numericality: { greater_than: 0 }
  validates :blocks_per_batch, numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  scope :mainnet, -> { where(network_type: "mainnet") }
  scope :testnet, -> { where(network_type: "testnet") }

  scope :enabled, -> { where(enabled: true) }

  # Get the active RPC URL (with fallback support)
  def active_rpc_url
    rpc_url
  end

  def status
    indexer_cursor&.status || "not_initialized"
  end

  def last_indexed_block
    indexer_cursor&.last_indexed_block || 0
  end

  # Default chain configs with public RPCs
  DEFAULTS = {
    1 => { name: "Ethereum", rpc_url: "https://eth.llamarpc.com", explorer_url: "https://etherscan.io", native_currency: "ETH", block_time_ms: 12000, network_type: "mainnet" },
    10 => { name: "Optimism", rpc_url: "https://mainnet.optimism.io", explorer_url: "https://optimistic.etherscan.io", native_currency: "ETH", block_time_ms: 2000, network_type: "mainnet" },
    137 => { name: "Polygon", rpc_url: "https://polygon-bor-rpc.publicnode.com", explorer_url: "https://polygonscan.com", native_currency: "MATIC", block_time_ms: 2000, network_type: "mainnet" },
    8453 => { name: "Base", rpc_url: "https://mainnet.base.org", explorer_url: "https://basescan.org", native_currency: "ETH", block_time_ms: 2000, network_type: "mainnet" },
    42161 => { name: "Arbitrum", rpc_url: "https://arb1.arbitrum.io/rpc", explorer_url: "https://arbiscan.io", native_currency: "ETH", block_time_ms: 250, network_type: "mainnet" },
    11155111 => { name: "Sepolia", rpc_url: "https://ethereum-sepolia-rpc.publicnode.com", explorer_url: "https://sepolia.etherscan.io", native_currency: "ETH", block_time_ms: 12000, network_type: "testnet" }
  }.freeze
end
