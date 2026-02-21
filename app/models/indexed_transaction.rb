# frozen_string_literal: true

class IndexedTransaction < ApplicationRecord
  belongs_to :indexed_block, foreign_key: :block_number, primary_key: :number, optional: true
  has_many :indexed_logs, foreign_key: :tx_hash, primary_key: :tx_hash

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :from_addr, ->(addr) { where(from_address: addr.downcase) }
  scope :to_addr, ->(addr) { where(to_address: addr.downcase) }
  scope :contract_creations, -> { where.not(contract_address: nil) }

  validates :tx_hash, :block_number, :from_address, :chain_id, presence: true

  before_validation :normalize_addresses

  private

  def normalize_addresses
    self.from_address = from_address&.downcase
    self.to_address = to_address&.downcase
    self.contract_address = contract_address&.downcase
  end
end
