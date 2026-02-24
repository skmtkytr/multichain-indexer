# frozen_string_literal: true

module Decoders
  # Decodes native ETH (or chain-native) transfers from transaction value field
  class NativeTransferDecoder
    def self.decode(context, transactions:, transfers:, **_opts)
      transactions.each do |tx|
        value = tx['value'].to_i(16)
        next if value.zero?

        transfers << context.build_transfer(
          tx_hash: tx['hash'],
          transfer_type: 'native',
          from_address: tx['from']&.downcase,
          to_address: tx['to']&.downcase,
          amount: value.to_s
        )
      end
    end
  end
end

TransferDecoder.register_extra_decoder(Decoders::NativeTransferDecoder)
