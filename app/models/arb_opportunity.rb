# frozen_string_literal: true

class ArbOpportunity < ApplicationRecord
  validates :chain_id, :block_number, :token_in, :pool_buy, :pool_sell, :arb_type, presence: true
  validates :arb_type, inclusion: { in: %w[direct triangular] }

  scope :profitable, ->(min_bps = 10) { where('spread_bps >= ?', min_bps) }
  scope :recent, ->(hours = 24) { where('created_at >= ?', hours.hours.ago) }

  def profitable?(gas_cost_bps = 5)
    spread_bps.to_f > gas_cost_bps
  end
end
