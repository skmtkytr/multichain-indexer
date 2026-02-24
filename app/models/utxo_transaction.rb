# frozen_string_literal: true

class UtxoTransaction < ApplicationRecord
  has_many :utxo_inputs, primary_key: :txid, foreign_key: :txid, dependent: :destroy
  has_many :utxo_outputs, primary_key: :txid, foreign_key: :txid, dependent: :destroy

  validates :chain_id, :txid, :block_number, presence: true
  validates :txid, uniqueness: { scope: :chain_id }

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :by_block, ->(block_number) { where(block_number: block_number) }
  scope :coinbase, -> { where(is_coinbase: true) }

  def total_input_value
    utxo_inputs.sum(:amount)
  end

  def total_output_value
    utxo_outputs.sum(:amount)
  end

  def calculated_fee
    return 0 if is_coinbase
    total_input_value - total_output_value
  end

  def tx_url
    config = ChainConfig.cached_find(chain_id)
    return nil unless config&.explorer_url
    "#{config.explorer_url}/tx/#{txid}"
  end
end
