# frozen_string_literal: true

class UtxoOutput < ApplicationRecord
  validates :chain_id, :txid, :vout_index, :amount, presence: true
  validates :vout_index, uniqueness: { scope: %i[chain_id txid] }

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :unspent, -> { where(spent: false) }
  scope :spent, -> { where(spent: true) }
  scope :by_address, ->(addr) { where(address: addr) }
  scope :confidential, -> { where(is_confidential: true) }

  def mark_spent!(by_txid, by_vin)
    update!(spent: true, spent_by_txid: by_txid, spent_by_vin: by_vin)
  end

  def op_return?
    script_type == 'nulldata'
  end

  def mweb?
    script_type&.start_with?('mweb')
  end

  # Format amount from satoshi to coin display
  def formatted_amount(decimals: 8)
    return '🔒 Confidential' if is_confidential
    (amount.to_f / (10**decimals)).round(decimals).to_s
  end
end
