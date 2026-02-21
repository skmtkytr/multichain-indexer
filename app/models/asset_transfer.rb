# frozen_string_literal: true

class AssetTransfer < ApplicationRecord
  # NOTE: composite FK (token_address + chain_id) — use method instead of belongs_to for correctness
  validates :tx_hash, :block_number, :chain_id, :transfer_type, :amount, presence: true
  validates :transfer_type, inclusion: { in: %w[native erc20 erc721 erc1155 internal] }

  scope :by_chain, ->(chain_id) { where(chain_id: chain_id) }
  scope :by_block, ->(block_number) { where(block_number: block_number) }
  scope :by_address, ->(address) { where('from_address = ? OR to_address = ?', address, address) }
  scope :by_token, ->(token_address) { where(token_address: token_address) }
  scope :native_transfers, -> { where(transfer_type: 'native') }
  scope :token_transfers, -> { where(transfer_type: %w[erc20 erc721 erc1155]) }
  scope :recent, -> { order(block_number: :desc, log_index: :desc) }

  before_save :normalize_addresses

  # Correct association: match both token_address AND chain_id
  def token_contract
    return nil if token_address.blank?
    @token_contract ||= TokenContract.find_by(address: token_address, chain_id: chain_id)
  end

  def native?
    transfer_type == 'native'
  end

  def internal?
    transfer_type == 'internal'
  end

  def token?
    %w[erc20 erc721 erc1155].include?(transfer_type)
  end

  def nft?
    %w[erc721 erc1155].include?(transfer_type)
  end

  def formatted_amount
    return '1 NFT' if nft? && token_id.present?
    return format_eth(amount) if native? || internal?
    return amount.to_s if token_contract.nil?

    token_contract.format_amount(amount)
  end

  def token_symbol
    return 'ETH' if native? || internal?
    return token_contract.display_name if token_contract
    return 'Unknown' if token_address.present?

    'ETH'
  end

  def description
    symbol = token_symbol
    amount_str = formatted_amount
    nft? && token_id.present? ? "#{symbol} ##{token_id}" : "#{amount_str} #{symbol}"
  end

  def tx_url
    chain_config = ChainConfig.find_by(chain_id: chain_id)
    return nil unless chain_config&.explorer_url
    "#{chain_config.explorer_url}/tx/#{tx_hash}"
  end

  private

  def normalize_addresses
    self.from_address = from_address&.downcase
    self.to_address = to_address&.downcase
    self.token_address = token_address&.downcase
  end

  def format_eth(wei)
    return '0' if wei.nil? || wei.zero?
    eth = wei.to_f / 1e18
    eth < 0.0001 ? '< 0.0001 ETH' : "#{'%.6f' % eth} ETH"
  end
end
