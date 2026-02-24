# frozen_string_literal: true

class AddressSubscription < ApplicationRecord
  has_many :webhook_deliveries, dependent: :destroy

  validates :address, presence: true
  validates :webhook_url, presence: true, format: { with: /\Ahttps?:\/\// }
  validates :direction, inclusion: { in: %w[both incoming outgoing] }
  validates :secret, presence: true

  before_validation :normalize_address, :generate_secret

  scope :active, -> { where(enabled: true) }

  # Find subscriptions matching a given transfer
  def self.matching(transfer)
    addr_down = nil
    from = transfer.from_address&.downcase
    to = transfer.to_address&.downcase

    subs = active.where(address: [from, to].compact.uniq)
    subs = subs.where('chain_id IS NULL OR chain_id = ?', transfer.chain_id)

    subs.select do |sub|
      addr = sub.address.downcase
      # Direction filter
      dir_ok = case sub.direction
               when 'incoming' then addr == to
               when 'outgoing' then addr == from
               else true
               end
      # Transfer type filter
      type_ok = sub.transfer_types.blank? || sub.transfer_types.include?(transfer.transfer_type)
      dir_ok && type_ok
    end
  end

  def auto_disable!
    update!(enabled: false) if failure_count >= max_failures
  end

  private

  def normalize_address
    self.address = address&.strip
    # Substrate SS58 addresses are case-sensitive; EVM/UTXO are not
    chain = chain_id.present? ? ChainConfig.cached_find(chain_id) : nil
    self.address = address&.downcase unless chain&.substrate?
  end

  def generate_secret
    self.secret ||= SecureRandom.hex(32)
  end
end
