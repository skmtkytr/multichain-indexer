# frozen_string_literal: true

class DexSwap < ApplicationRecord
  belongs_to :dex_pool, ->(swap) { where(chain_id: swap.chain_id) },
             foreign_key: :pool_address, primary_key: :pool_address, optional: true

  validates :chain_id, :block_number, :tx_hash, :log_index, :pool_address,
            :amount_in, :amount_out, presence: true

  scope :for_block, ->(chain_id, block_number) {
    where(chain_id: chain_id, block_number: block_number)
  }

  scope :for_pair, ->(chain_id, token_a, token_b) {
    where(chain_id: chain_id).where(
      '(token_in = ? AND token_out = ?) OR (token_in = ? AND token_out = ?)',
      token_a, token_b, token_b, token_a
    )
  }
end
