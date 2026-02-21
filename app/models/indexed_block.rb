# frozen_string_literal: true

class IndexedBlock < ApplicationRecord
  has_many :indexed_transactions, foreign_key: :block_number, primary_key: :number

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :recent, -> { order(number: :desc) }

  validates :number, :block_hash, :parent_hash, :timestamp, :chain_id, presence: true
  validates :number, uniqueness: { scope: :chain_id }
end
