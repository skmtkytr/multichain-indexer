# frozen_string_literal: true

class EventSignature < ApplicationRecord
  validates :signature_hash, presence: true, uniqueness: true
  validates :event_name, :full_signature, presence: true

  # Find signature by topic0 hash
  def self.find_by_topic0(topic0)
    find_by(signature_hash: topic0)
  end

  # Create from event signature string
  def self.from_signature(signature)
    hash = Digest::Keccak.hexdigest(signature)[0..7] # First 4 bytes
    create!(
      signature_hash: "0x#{hash}",
      event_name: extract_event_name(signature),
      full_signature: signature
    )
  end

  def self.extract_event_name(signature)
    signature.match(/(\w+)\(/)[1]
  rescue StandardError
    'Unknown'
  end
end
