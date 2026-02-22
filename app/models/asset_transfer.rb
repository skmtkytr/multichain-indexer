# frozen_string_literal: true

class AssetTransfer < ApplicationRecord
  # NOTE: composite FK (token_address + chain_id) — use method instead of belongs_to for correctness
  validates :tx_hash, :block_number, :chain_id, :transfer_type, :amount, presence: true
  validates :transfer_type, inclusion: { in: %w[native erc20 erc721 erc1155 internal withdrawal mweb_pegin mweb_pegout mweb_confidential shielded_in shielded_out] }

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

  def withdrawal?
    transfer_type == 'withdrawal'
  end

  def confidential?
    confidential == true
  end

  def mweb?
    privacy_protocol == 'mweb'
  end

  def token?
    %w[erc20 erc721 erc1155].include?(transfer_type)
  end

  def nft?
    %w[erc721 erc1155].include?(transfer_type)
  end

  def formatted_amount
    return '🔒 Confidential' if confidential?
    return '1 NFT' if nft? && token_id.present?
    if native? || internal? || withdrawal? || mweb?
      chain = ChainConfig.find_by(chain_id: chain_id)
      if chain&.chain_type == 'utxo'
        return format_satoshi(amount, chain&.native_currency || 'BTC')
      end
      return format_eth(amount)
    end
    return amount.to_s if token_contract.nil?

    token_contract.format_amount(amount)
  end

  def token_symbol
    chain = ChainConfig.find_by(chain_id: chain_id)
    native = chain&.native_currency || 'ETH'
    return native if native? || internal? || withdrawal? || mweb?
    return token_contract.display_name if token_contract
    return 'Unknown' if token_address.present?

    native
  end

  def description
    symbol = token_symbol
    amount_str = formatted_amount
    nft? && token_id.present? ? "#{symbol} ##{token_id}" : "#{amount_str} #{symbol}"
  end

  def tx_url
    return nil if withdrawal? # pseudo tx_hash, not a real transaction
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

  def format_satoshi(satoshi, symbol = 'BTC')
    return '0' if satoshi.nil? || satoshi.zero?
    coin = satoshi.to_f / 1e8
    coin < 0.00000001 ? "< 0.00000001 #{symbol}" : "#{'%.8f' % coin} #{symbol}"
  end
end
