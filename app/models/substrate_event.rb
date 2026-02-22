# frozen_string_literal: true

class SubstrateEvent < ApplicationRecord
  validates :chain_id, :block_number, :event_index, :pallet, :method, presence: true
  validates :event_index, uniqueness: { scope: %i[chain_id block_number] }

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :by_block, ->(block_number) { where(block_number: block_number) }
  scope :by_pallet, ->(pallet) { where(pallet: pallet) }
  scope :transfers, -> { where(pallet: %w[balances assets foreignAssets], method: %w[Transfer Transferred]) }

  def full_method
    "#{pallet}.#{method}"
  end
end
