# frozen_string_literal: true

module Decoders
  # Decodes beacon chain validator withdrawals (Shanghai/Capella upgrade)
  # Amount is in Gwei, converted to Wei
  class BeaconWithdrawalDecoder
    ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

    def self.decode(context, withdrawals:, transfers:, **_opts)
      return if withdrawals.nil? || withdrawals.empty?

      withdrawals.each_with_index do |w, idx|
        amount_gwei = w['amount'].to_i(16)
        amount_wei = amount_gwei * 1_000_000_000
        next if amount_wei.zero?

        transfers << context.build_transfer(
          tx_hash: "withdrawal-#{context.block_number}-#{w['index'].to_i(16)}",
          transfer_type: 'withdrawal',
          from_address: ZERO_ADDRESS,
          to_address: w['address']&.downcase,
          amount: amount_wei.to_s,
          trace_index: idx
        )
      end
    end
  end
end

TransferDecoder.register_extra_decoder(Decoders::BeaconWithdrawalDecoder)
