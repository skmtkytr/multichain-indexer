# frozen_string_literal: true

module Decoders
  # Decodes ERC-1155 TransferSingle and TransferBatch events.
  #
  # TransferSingle(operator, from, to, id, value)
  #   topic0: 0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62
  #   topics: [topic0, operator, from, to]
  #   data: [id (uint256), value (uint256)]
  #
  # TransferBatch(operator, from, to, ids[], values[])
  #   topic0: 0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb
  #   topics: [topic0, operator, from, to]
  #   data: ABI-encoded arrays of ids and values
  class Erc1155Decoder
    TRANSFER_SINGLE = '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62'
    TRANSFER_BATCH  = '0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb'

    def self.decode_single(context, log, transfers)
      topics = log['topics'] || []
      return if topics.size < 4

      from = TransferDecoder.address_from_topic(topics[2])
      to = TransferDecoder.address_from_topic(topics[3])
      return unless from && to

      data = log['data'] || '0x'
      # data = id (32 bytes) + value (32 bytes) = 130 hex chars (0x + 128)
      return if data.length < 130

      id = data[2, 64].to_i(16)
      value = data[66, 64].to_i(16)

      transfers << context.build_transfer(
        tx_hash: log['transactionHash'],
        transfer_type: 'erc1155',
        token_address: log['address']&.downcase,
        from_address: from,
        to_address: to,
        amount: value.to_s,
        token_id: id.to_s,
        log_index: log['logIndex']&.to_i(16) || -1
      )
    end

    def self.decode_batch(context, log, transfers)
      topics = log['topics'] || []
      return if topics.size < 4

      from = TransferDecoder.address_from_topic(topics[2])
      to = TransferDecoder.address_from_topic(topics[3])
      return unless from && to

      data = log['data'] || '0x'
      hex = data.sub(/\A0x/, '')
      # ABI encoding: offset_ids (32B) + offset_values (32B) + ids_length + ids... + values_length + values...
      return if hex.length < 256 # minimum: 2 offsets + 2 lengths + at least 1 id + 1 value

      begin
        ids_offset = hex[0, 64].to_i(16) * 2   # byte offset → hex char offset
        vals_offset = hex[64, 64].to_i(16) * 2

        ids_count = hex[ids_offset, 64].to_i(16)
        vals_count = hex[vals_offset, 64].to_i(16)
        return unless ids_count == vals_count && ids_count > 0 && ids_count <= 1000

        log_idx = log['logIndex']&.to_i(16) || -1
        tx_hash = log['transactionHash']
        address = log['address']&.downcase

        ids_count.times do |i|
          id = hex[ids_offset + 64 + (i * 64), 64].to_i(16)
          value = hex[vals_offset + 64 + (i * 64), 64].to_i(16)

          # Each item in batch gets a unique trace_index to avoid unique constraint collision
          transfers << context.build_transfer(
            tx_hash: tx_hash,
            transfer_type: 'erc1155',
            token_address: address,
            from_address: from,
            to_address: to,
            amount: value.to_s,
            token_id: id.to_s,
            log_index: log_idx,
            trace_index: i  # differentiate items within same log
          )
        end
      rescue StandardError => e
        Rails.logger.warn("ERC-1155 TransferBatch decode failed: #{e.message}")
      end
    end

    # Entry point for log decoder registry
    def self.decode_log(context, log, transfers)
      topic0 = log['topics']&.first
      case topic0
      when TRANSFER_SINGLE
        decode_single(context, log, transfers)
      when TRANSFER_BATCH
        decode_batch(context, log, transfers)
      end
    end
  end
end

# Register both event signatures
TransferDecoder.register_log_decoder(Decoders::Erc1155Decoder::TRANSFER_SINGLE, Decoders::Erc1155Decoder)
TransferDecoder.register_log_decoder(Decoders::Erc1155Decoder::TRANSFER_BATCH, Decoders::Erc1155Decoder)
