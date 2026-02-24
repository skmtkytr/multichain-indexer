# frozen_string_literal: true

module Decoders
  # Decodes ERC-20 Transfer(address,address,uint256) events.
  # Also handles ERC-721 when 4 topics are present (token_id in topic3).
  #
  # topic0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
  # topics[1]: from (padded address)
  # topics[2]: to (padded address)
  # topics[3]: token_id (ERC-721 only)
  # data: amount (ERC-20 only)
  class Erc20TransferDecoder
    TOPIC0 = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'

    def self.decode_log(context, log, transfers)
      topics = log['topics'] || []
      return if topics.size < 3

      from = TransferDecoder.address_from_topic(topics[1])
      to = TransferDecoder.address_from_topic(topics[2])
      return unless from && to

      log_idx = log['logIndex']&.to_i(16) || -1
      tx_hash = log['transactionHash']
      address = log['address']&.downcase

      if topics.size == 4
        # ERC-721: token_id in topic3
        token_id = topics[3].to_i(16)
        transfers << context.build_transfer(
          tx_hash: tx_hash,
          transfer_type: 'erc721',
          token_address: address,
          from_address: from,
          to_address: to,
          amount: '1',
          token_id: token_id.to_s,
          log_index: log_idx
        )
      else
        # ERC-20: amount in data
        data = log['data'] || '0x'
        amount = data.to_i(16)
        transfers << context.build_transfer(
          tx_hash: tx_hash,
          transfer_type: 'erc20',
          token_address: address,
          from_address: from,
          to_address: to,
          amount: amount.to_s,
          log_index: log_idx
        )
      end
    end
  end
end

TransferDecoder.register_log_decoder(
  Decoders::Erc20TransferDecoder::TOPIC0,
  Decoders::Erc20TransferDecoder
)
