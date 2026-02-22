# frozen_string_literal: true

class SubstrateExtrinsic < ApplicationRecord
  has_many :substrate_events,
           primary_key: %i[chain_id block_number extrinsic_index],
           foreign_key: %i[chain_id block_number extrinsic_index]

  validates :chain_id, :block_number, :extrinsic_index, :pallet, :method, presence: true
  validates :extrinsic_index, uniqueness: { scope: %i[chain_id block_number] }

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :by_block, ->(block_number) { where(block_number: block_number) }
  scope :user_signed, -> { where.not(signer: nil) }
  scope :by_pallet, ->(pallet) { where(pallet: pallet) }

  def inherent?
    signer.nil?
  end

  def full_method
    "#{pallet}.#{method}"
  end

  def tx_url
    config = ChainConfig.find_by(chain_id: chain_id)
    return nil unless config&.explorer_url && extrinsic_hash
    "#{config.explorer_url}/extrinsic/#{extrinsic_hash}"
  end
end
