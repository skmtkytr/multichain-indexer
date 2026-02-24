# frozen_string_literal: true

module Decoders
  # Decodes WETH Deposit and Withdrawal events.
  # These represent wrapping/unwrapping of native ETH to/from WETH ERC-20.
  #
  # Deposit(address dst, uint wad)
  #   topic0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
  #   Mint WETH: 0x000...000 → dst
  #
  # Withdrawal(address src, uint wad)
  #   topic0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
  #   Burn WETH: src → 0x000...000
  class WethDecoder
    ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

    DEPOSIT_TOPIC    = '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c'
    WITHDRAWAL_TOPIC = '0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65'

    def self.decode_log(context, log, transfers)
      topics = log['topics'] || []
      return if topics.size < 2

      topic0 = topics.first
      address = log['address']&.downcase
      data = log['data'] || '0x'
      amount = data.to_i(16)
      log_idx = log['logIndex']&.to_i(16) || -1
      tx_hash = log['transactionHash']

      case topic0
      when DEPOSIT_TOPIC
        to = TransferDecoder.address_from_topic(topics[1])
        transfers << context.build_transfer(
          tx_hash: tx_hash,
          transfer_type: 'erc20',
          token_address: address,
          from_address: ZERO_ADDRESS,
          to_address: to,
          amount: amount.to_s,
          log_index: log_idx
        )
      when WITHDRAWAL_TOPIC
        from = TransferDecoder.address_from_topic(topics[1])
        transfers << context.build_transfer(
          tx_hash: tx_hash,
          transfer_type: 'erc20',
          token_address: address,
          from_address: from,
          to_address: ZERO_ADDRESS,
          amount: amount.to_s,
          log_index: log_idx
        )
      end
    end
  end
end

TransferDecoder.register_log_decoder(Decoders::WethDecoder::DEPOSIT_TOPIC, Decoders::WethDecoder)
TransferDecoder.register_log_decoder(Decoders::WethDecoder::WITHDRAWAL_TOPIC, Decoders::WethDecoder)
