# frozen_string_literal: true

class TokenContract < ApplicationRecord
  has_many :asset_transfers, ->(token) { where(chain_id: token.chain_id) },
           foreign_key: :token_address, primary_key: :address

  validates :address, presence: true, length: { is: 42 }
  validates :chain_id, presence: true
  validates :standard, inclusion: { in: %w[erc20 erc721 erc1155 unknown], allow_blank: true }

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :by_standard, ->(standard) { where(standard: standard) }

  before_save :normalize_address

  # Find or create token contract
  def self.find_or_create_for(address, chain_id, metadata = {})
    normalized_address = address&.downcase
    return nil if normalized_address.blank?

    find_by(address: normalized_address, chain_id: chain_id) ||
      create!(
        address: normalized_address,
        chain_id: chain_id,
        **metadata
      )
  end

  # Human-readable amount based on decimals
  def format_amount(raw_amount)
    return raw_amount.to_s if decimals.nil? || decimals.zero?

    amount = BigDecimal(raw_amount.to_s)
    divisor = BigDecimal(10)**decimals
    (amount / divisor).to_f
  end

  # Display name (symbol or name or address)
  def display_name
    symbol.presence || name.presence || address
  end

  def erc20?
    standard == 'erc20'
  end

  def erc721?
    standard == 'erc721'
  end

  def erc1155?
    standard == 'erc1155'
  end

  def nft?
    erc721? || erc1155?
  end

  private

  def normalize_address
    self.address = address&.downcase
  end
end
