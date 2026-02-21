class ChainConfig < ApplicationRecord
  has_one :indexer_cursor, primary_key: :chain_id, foreign_key: :chain_id

  validates :chain_id, presence: true, uniqueness: true
  validates :name, :rpc_url, presence: true
  validates :poll_interval_seconds, numericality: { greater_than: 0 }
  validates :blocks_per_batch, numericality: { greater_than: 0, less_than_or_equal_to: 100 }

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
    1 => { name: "Ethereum", rpc_url: "https://eth.llamarpc.com", native_currency: "ETH", block_time_ms: 12000 },
    10 => { name: "Optimism", rpc_url: "https://mainnet.optimism.io", native_currency: "ETH", block_time_ms: 2000 },
    137 => { name: "Polygon", rpc_url: "https://polygon-bor-rpc.publicnode.com", native_currency: "MATIC", block_time_ms: 2000 },
    8453 => { name: "Base", rpc_url: "https://mainnet.base.org", native_currency: "ETH", block_time_ms: 2000 },
    42161 => { name: "Arbitrum", rpc_url: "https://arb1.arbitrum.io/rpc", native_currency: "ETH", block_time_ms: 250 },
    11155111 => { name: "Sepolia", rpc_url: "https://rpc.sepolia.org", native_currency: "ETH", block_time_ms: 12000 }
  }.freeze
end
