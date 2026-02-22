# frozen_string_literal: true

class UtxoInput < ApplicationRecord
  validates :chain_id, :txid, :vin_index, presence: true
  validates :vin_index, uniqueness: { scope: %i[chain_id txid] }

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :coinbase, -> { where(is_coinbase: true) }

  def resolved?
    address.present? && amount.present?
  end

  def coinbase?
    is_coinbase
  end
end
