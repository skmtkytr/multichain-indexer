# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  class DecodeTransfersActivity < Temporalio::Activity::Definition
    # ERC-20/721 Transfer topic0
    TRANSFER_TOPIC = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
    ERC1155_SINGLE = '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62'
    ERC1155_BATCH = '0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb'
    WETH_DEPOSIT = '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c'
    WETH_WITHDRAWAL = '0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65'

    def execute(params)
      action = params['action']
      case action
      when 'decode_and_store'
        decode_and_store(params)
      when 'enqueue_token_metadata'
        enqueue_token_metadata(params)
      when 'fetch_token_metadata'
        fetch_token_metadata(params)
      end
    end

    private

    def decode_and_store(params)
      block_number = params['block_number']
      chain_id = params['chain_id']
      transactions = params['transactions'] || []
      logs = params['logs'] || []
      traces = params['traces'] || []

      transfers = []

      # 1. Native ETH from tx.value
      transactions.each do |tx|
        value = tx['value'].to_i(16)
        next if value.zero?

        transfers << {
          tx_hash: tx['hash'],
          block_number: block_number,
          chain_id: chain_id,
          transfer_type: 'native',
          token_address: nil,
          from_address: tx['from']&.downcase,
          to_address: tx['to']&.downcase,
          amount: value.to_s,
          token_id: nil,
          log_index: -1, # Use -1 instead of nil for unique constraint
          trace_index: -1,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # 2. ERC-20/721/1155 Transfer events from logs
      logs.each do |log|
        topic0 = log['topics']&.first
        case topic0
        when TRANSFER_TOPIC
          decode_transfer_event(log, chain_id, block_number, transfers)
        when ERC1155_SINGLE
          decode_erc1155_single(log, chain_id, block_number, transfers)
        when ERC1155_BATCH
          decode_erc1155_batch(log, chain_id, block_number, transfers)
        when WETH_DEPOSIT
          decode_weth_deposit(log, chain_id, block_number, transfers)
        when WETH_WITHDRAWAL
          decode_weth_withdrawal(log, chain_id, block_number, transfers)
        end
      end

      # 3. Internal transactions from traces
      traces.each_with_index do |trace, idx|
        value = parse_trace_value(trace)
        next if value.zero?

        transfers << {
          tx_hash: extract_trace_tx_hash(trace),
          block_number: block_number,
          chain_id: chain_id,
          transfer_type: 'internal',
          token_address: nil,
          from_address: extract_trace_from(trace)&.downcase,
          to_address: extract_trace_to(trace)&.downcase,
          amount: value.to_s,
          token_id: nil,
          log_index: -1,
          trace_index: idx,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # Bulk insert with upsert to handle duplicates
      if transfers.any?
        AssetTransfer.upsert_all(transfers, unique_by: %i[chain_id tx_hash transfer_type log_index trace_index])
      end

      # Collect unique token addresses for metadata fetch
      token_addresses = transfers
                        .select { |t| t[:token_address] }
                        .map { |t| t[:token_address] }
                        .uniq

      Rails.logger.info(
        "Decoded #{transfers.size} transfers for block ##{block_number} on chain #{chain_id}: " \
        "#{transfers.count { |t| t[:transfer_type] == 'native' }} native, " \
        "#{transfers.count { |t| %w[erc20 erc721 erc1155].include?(t[:transfer_type]) }} token, " \
        "#{transfers.count { |t| t[:transfer_type] == 'internal' }} internal"
      )

      { transfers_count: transfers.size, token_addresses: token_addresses }
    end

    def fetch_token_metadata(params)
      chain_id = params['chain_id']
      token_addresses = params['token_addresses'] || []

      return { processed: 0 } if token_addresses.empty?

      rpc = EthereumRpc.new(chain_id: chain_id)
      processed = 0

      token_addresses.each do |address|
        next if address.blank?

        # Skip if already exists
        existing = TokenContract.find_by(address: address.downcase, chain_id: chain_id)
        next if existing

        begin
          metadata = rpc.get_token_metadata(address)
          TokenContract.find_or_create_by!(address: address.downcase, chain_id: chain_id) do |tc|
            tc.name = metadata[:name]
            tc.symbol = metadata[:symbol]
            tc.decimals = metadata[:decimals]
            tc.standard = metadata[:standard]
          end
          processed += 1
          Rails.logger.info("Fetched metadata for token #{address} on chain #{chain_id}")
        rescue StandardError => e
          Rails.logger.warn("Failed to fetch metadata for #{address} on chain #{chain_id}: #{e.message}")
          TokenContract.find_or_create_by!(address: address.downcase, chain_id: chain_id) do |tc|
            tc.standard = 'unknown'
          end
        end
      end

      { processed: processed }
    end

    # Lightweight: just create placeholder records in DB, no RPC calls
    def enqueue_token_metadata(params)
      chain_id = params['chain_id']
      token_addresses = params['token_addresses'] || []
      enqueued = 0

      token_addresses.each do |address|
        next if address.blank?
        TokenContract.find_or_create_by!(address: address.downcase, chain_id: chain_id) do |tc|
          tc.standard = 'unknown'
          enqueued += 1
        end
      rescue StandardError => e
        Rails.logger.debug("Token enqueue failed for #{address}: #{e.message}")
      end

      { enqueued: enqueued }
    end

    # Decode ERC-20/721 Transfer event
    def decode_transfer_event(log, chain_id, block_number, transfers)
      topics = log['topics'] || []
      return if topics.size < 3

      from = begin
        "0x#{topics[1][-40..]}"
      rescue StandardError
        nil
      end
      to = begin
        "0x#{topics[2][-40..]}"
      rescue StandardError
        nil
      end
      data = log['data'] || '0x'

      # ERC-20: amount in data, ERC-721: tokenId in topics[3]
      if topics.size == 4
        # ERC-721: tokenId in topics[3]
        token_id = topics[3].to_i(16)
        transfers << build_transfer(log, chain_id, block_number, 'erc721', from, to, '1', token_id)
      else
        # ERC-20: amount in data
        amount = data.to_i(16)
        transfers << build_transfer(log, chain_id, block_number, 'erc20', from, to, amount.to_s, nil)
      end
    end

    # Decode ERC-1155 TransferSingle event
    def decode_erc1155_single(log, chain_id, block_number, transfers)
      topics = log['topics'] || []
      return if topics.size < 4

      # topics[0] = event signature
      # topics[1] = operator (indexed)
      # topics[2] = from (indexed)
      # topics[3] = to (indexed)
      # data = id + value

      from = begin
        "0x#{topics[2][-40..]}"
      rescue StandardError
        nil
      end
      to = begin
        "0x#{topics[3][-40..]}"
      rescue StandardError
        nil
      end
      data = log['data'] || '0x'

      return if data.length < 130 # Need at least 64 bytes for id + value

      # Decode id and value from data (each 32 bytes)
      id = data[2, 64].to_i(16)
      value = data[66, 64].to_i(16)

      transfers << build_transfer(log, chain_id, block_number, 'erc1155', from, to, value.to_s, id)
    end

    # Decode ERC-1155 TransferBatch event
    def decode_erc1155_batch(log, chain_id, block_number, transfers)
      topics = log['topics'] || []
      return if topics.size < 4

      from = begin
        "0x#{topics[2][-40..]}"
      rescue StandardError
        nil
      end
      to = begin
        "0x#{topics[3][-40..]}"
      rescue StandardError
        nil
      end

      # For batches, we'll create one transfer per id/value pair
      # This is simplified - full ABI decoding would be more complex
      transfers << build_transfer(log, chain_id, block_number, 'erc1155', from, to, '1', nil)
    end

    # Decode WETH Deposit event
    def decode_weth_deposit(log, chain_id, block_number, transfers)
      topics = log['topics'] || []
      return if topics.size < 2

      to = begin
        "0x#{topics[1][-40..]}"
      rescue StandardError
        nil
      end
      data = log['data'] || '0x'
      amount = data.to_i(16)

      transfers << build_transfer(log, chain_id, block_number, 'erc20', '0x0000000000000000000000000000000000000000',
                                  to, amount.to_s, nil)
    end

    # Decode WETH Withdrawal event
    def decode_weth_withdrawal(log, chain_id, block_number, transfers)
      topics = log['topics'] || []
      return if topics.size < 2

      from = begin
        "0x#{topics[1][-40..]}"
      rescue StandardError
        nil
      end
      data = log['data'] || '0x'
      amount = data.to_i(16)

      transfers << build_transfer(log, chain_id, block_number, 'erc20', from,
                                  '0x0000000000000000000000000000000000000000', amount.to_s, nil)
    end

    # Build transfer record
    def build_transfer(log, chain_id, block_number, transfer_type, from, to, amount, token_id)
      {
        tx_hash: log['transactionHash'],
        block_number: block_number,
        chain_id: chain_id,
        transfer_type: transfer_type,
        token_address: log['address']&.downcase,
        from_address: from&.downcase,
        to_address: to&.downcase,
        amount: amount,
        token_id: token_id&.to_s,
        log_index: log['logIndex']&.to_i(16) || -1,
        trace_index: -1,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # Parse trace value from different trace formats
    def parse_trace_value(trace)
      if trace['value'] # Geth format
        trace['value'].to_i(16)
      elsif trace.dig('action', 'value') # Parity format
        trace.dig('action', 'value').to_i(16)
      else
        0
      end
    end

    # Extract transaction hash from trace
    def extract_trace_tx_hash(trace)
      trace['transactionHash'] || trace['hash']
    end

    # Extract from address from trace
    def extract_trace_from(trace)
      if trace['from']
        trace['from']
      elsif trace.dig('action', 'from')
        trace.dig('action', 'from')
      end
    end

    # Extract to address from trace
    def extract_trace_to(trace)
      if trace['to']
        trace['to']
      elsif trace.dig('action', 'to')
        trace.dig('action', 'to')
      end
    end
  end
end
