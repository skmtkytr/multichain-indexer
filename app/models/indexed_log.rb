class IndexedLog < ApplicationRecord
  belongs_to :indexed_transaction, foreign_key: :tx_hash, primary_key: :tx_hash, optional: true

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :by_contract, ->(addr) { where(address: addr.downcase) }
  scope :by_event, ->(topic0) { where(topic0: topic0) }

  # Common ERC-20 event signatures
  TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  APPROVAL_TOPIC = "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"

  scope :transfers, -> { where(topic0: TRANSFER_TOPIC) }
  scope :approvals, -> { where(topic0: APPROVAL_TOPIC) }

  validates :tx_hash, :block_number, :log_index, :address, :chain_id, presence: true

  before_validation :normalize_address

  private

  def normalize_address
    self.address = address&.downcase
  end
end
