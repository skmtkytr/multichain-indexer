# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  class FetchBlockActivity < Temporalio::Activity::Definition
    def execute(params)
      action = params['action']
      chain_id = params['chain_id']

      _execute(action, chain_id, params)
    rescue EthereumRpc::NonRetryableError => e
      raise Temporalio::Error::ApplicationError.new(e.message, type: 'NonRetryableError', non_retryable: true)
    end

    private

    def _execute(action, chain_id, params)

      case action
      when 'get_latest'
        config = ChainConfig.find_by(chain_id: chain_id)
        rpc = EthereumRpc.new(chain_id: chain_id)
        tag = config&.block_tag || 'finalized'
        block_num = rpc.get_block_number(tag: tag)

        # Fallback: if finalized/safe returns nil (unsupported), use latest - confirmation_blocks
        if block_num.nil?
          latest = rpc.get_block_number(tag: 'latest')
          confirmations = config&.confirmation_blocks || 0
          block_num = [latest - confirmations, 0].max
        end

        block_num

      when 'fetch_and_store'
        # Combined: fetch from RPC + store to DB in one activity.
        # Returns only a small summary (no large data through Temporal gRPC).
        fetch_and_store(params)

      when 'fetch_full_block'
        # Legacy: returns full data through Temporal (may exceed gRPC limit on large blocks)
        block_number = params['block_number']
        config = ChainConfig.find_by(chain_id: chain_id)
        supports_receipts = config&.supports_block_receipts != false

        rpc = EthereumRpc.new(chain_id: chain_id)
        result = rpc.fetch_full_block(block_number, supports_block_receipts: supports_receipts)

        if result.nil?
          Rails.logger.warn("Block #{block_number} not found on chain #{chain_id}")
          return nil
        end

        result

      when 'fetch_block'
        block_number = params['block_number']
        rpc = EthereumRpc.new(chain_id: chain_id)
        block_data = rpc.get_block_by_number(block_number, full_transactions: true)
        block_data&.merge('chain_id' => chain_id)
      end
    end

    private

    def fetch_and_store(params)
      chain_id = params['chain_id']
      block_number = params['block_number']

      config = ChainConfig.find_by(chain_id: chain_id)
      supports_receipts = config&.supports_block_receipts != false

      # 1. Fetch from RPC
      rpc = EthereumRpc.new(chain_id: chain_id)
      full_data = rpc.fetch_full_block(block_number, supports_block_receipts: supports_receipts)

      if full_data.nil?
        Rails.logger.warn("Block #{block_number} not found on chain #{chain_id}")
        return nil
      end

      block_data = full_data['block']
      receipts = full_data['receipts'] || []
      logs = full_data['logs'] || []

      # 2. Build records
      block_num = block_data['number'].to_i(16)
      receipt_by_hash = receipts.each_with_object({}) { |r, h| h[r['transactionHash']] = r if r }

      tx_records = (block_data['transactions'] || []).map do |tx_data|
        receipt = receipt_by_hash[tx_data['hash']]
        {
          tx_hash: tx_data['hash'],
          block_number: block_num,
          tx_index: tx_data['transactionIndex'].to_i(16),
          from_address: tx_data['from']&.downcase,
          to_address: tx_data['to']&.downcase,
          value: tx_data['value'].to_i(16).to_s,
          gas_price: tx_data['gasPrice']&.then { |v| v.to_i(16).to_s },
          max_fee_per_gas: tx_data['maxFeePerGas']&.then { |v| v.to_i(16).to_s },
          max_priority_fee_per_gas: tx_data['maxPriorityFeePerGas']&.then { |v| v.to_i(16).to_s },
          gas_used: receipt&.dig('gasUsed')&.then { |v| v.to_i(16).to_s },
          input_data: tx_data['input'],
          status: receipt&.dig('status')&.to_i(16),
          contract_address: receipt&.dig('contractAddress')&.downcase,
          chain_id: chain_id,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      log_records = logs.map do |log|
        topics = log['topics'] || []
        {
          tx_hash: log['transactionHash'],
          block_number: log['blockNumber'].to_i(16),
          log_index: log['logIndex'].to_i(16),
          address: log['address']&.downcase,
          topic0: topics[0],
          topic1: topics[1],
          topic2: topics[2],
          topic3: topics[3],
          data: log['data'],
          removed: log['removed'] || false,
          chain_id: chain_id,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # 3. Store in DB (single transaction)
      ActiveRecord::Base.transaction do
        IndexedBlock.upsert(
          {
            number: block_num,
            block_hash: block_data['hash'],
            parent_hash: block_data['parentHash'],
            timestamp: block_data['timestamp'].to_i(16),
            miner: block_data['miner']&.downcase,
            gas_used: block_data['gasUsed']&.then { |v| v.to_i(16).to_s },
            gas_limit: block_data['gasLimit']&.then { |v| v.to_i(16).to_s },
            base_fee_per_gas: block_data['baseFeePerGas']&.then { |v| v.to_i(16).to_s },
            transaction_count: tx_records.size,
            chain_id: chain_id,
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: %i[chain_id number]
        )
        IndexedTransaction.upsert_all(tx_records, unique_by: %i[chain_id tx_hash]) if tx_records.any?
        IndexedLog.upsert_all(log_records, unique_by: %i[chain_id block_number log_index]) if log_records.any?
      end

      # 4. Decode asset transfers (in-process, no Temporal roundtrip)
      transfers = decode_transfers(chain_id, block_num, block_data['transactions'] || [], logs, block_data['withdrawals'] || [])
      token_addresses = transfers[:token_addresses]

      # 5. Enqueue token metadata placeholders
      if token_addresses.any?
        token_addresses.each do |address|
          next if address.blank?
          TokenContract.find_or_create_by!(address: address.downcase, chain_id: chain_id) do |tc|
            tc.standard = 'unknown'
          end
        rescue StandardError => e
          Rails.logger.debug("Token enqueue failed for #{address}: #{e.message}")
        end
      end

      Rails.logger.info(
        "Indexed block ##{block_num} on chain #{chain_id}: " \
        "#{tx_records.size} txs, #{log_records.size} logs, #{transfers[:count]} transfers"
      )

      # Return only summary (tiny payload)
      {
        'block_number' => block_num,
        'chain_id' => chain_id,
        'tx_count' => tx_records.size,
        'log_count' => log_records.size,
        'transfer_count' => transfers[:count],
        'token_addresses_count' => token_addresses.size
      }
    end

    # Decode transfers inline (same logic as DecodeTransfersActivity but without Temporal overhead)
    def decode_transfers(chain_id, block_number, transactions, logs, withdrawals = [])
      transfer_topic = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
      erc1155_single = '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62'
      weth_deposit = '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c'
      weth_withdrawal = '0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65'

      transfers = []

      # Beacon chain validator withdrawals (Shanghai/Capella upgrade, amount in Gwei)
      withdrawals.each_with_index do |w, idx|
        amount_gwei = w['amount'].to_i(16)
        amount_wei = amount_gwei * 1_000_000_000 # Gwei → Wei
        next if amount_wei.zero?

        transfers << {
          tx_hash: "withdrawal-#{block_number}-#{w['index'].to_i(16)}",
          block_number: block_number, chain_id: chain_id,
          transfer_type: 'withdrawal', token_address: nil,
          from_address: '0x0000000000000000000000000000000000000000',
          to_address: w['address']&.downcase,
          amount: amount_wei.to_s, token_id: nil,
          log_index: -1, trace_index: idx,
          created_at: Time.current, updated_at: Time.current
        }
      end

      # Native ETH
      transactions.each do |tx|
        value = tx['value'].to_i(16)
        next if value.zero?

        transfers << {
          tx_hash: tx['hash'], block_number: block_number, chain_id: chain_id,
          transfer_type: 'native', token_address: nil,
          from_address: tx['from']&.downcase, to_address: tx['to']&.downcase,
          amount: value.to_s, token_id: nil, log_index: -1, trace_index: -1,
          created_at: Time.current, updated_at: Time.current
        }
      end

      # Token events
      logs.each do |log|
        topic0 = log['topics']&.first
        topics = log['topics'] || []
        log_idx = log['logIndex']&.to_i(16) || -1
        tx_hash = log['transactionHash']
        address = log['address']&.downcase
        data = log['data'] || '0x'

        case topic0
        when transfer_topic
          next if topics.size < 3
          from = "0x#{topics[1][-40..]}" rescue nil
          to = "0x#{topics[2][-40..]}" rescue nil
          if topics.size == 4
            token_id = topics[3].to_i(16)
            transfers << { tx_hash: tx_hash, block_number: block_number, chain_id: chain_id,
                          transfer_type: 'erc721', token_address: address,
                          from_address: from&.downcase, to_address: to&.downcase,
                          amount: '1', token_id: token_id.to_s, log_index: log_idx, trace_index: -1,
                          created_at: Time.current, updated_at: Time.current }
          else
            amount = data.to_i(16)
            transfers << { tx_hash: tx_hash, block_number: block_number, chain_id: chain_id,
                          transfer_type: 'erc20', token_address: address,
                          from_address: from&.downcase, to_address: to&.downcase,
                          amount: amount.to_s, token_id: nil, log_index: log_idx, trace_index: -1,
                          created_at: Time.current, updated_at: Time.current }
          end
        when erc1155_single
          next if topics.size < 4
          from = "0x#{topics[2][-40..]}" rescue nil
          to = "0x#{topics[3][-40..]}" rescue nil
          next if data.length < 130
          id = data[2, 64].to_i(16)
          value = data[66, 64].to_i(16)
          transfers << { tx_hash: tx_hash, block_number: block_number, chain_id: chain_id,
                        transfer_type: 'erc1155', token_address: address,
                        from_address: from&.downcase, to_address: to&.downcase,
                        amount: value.to_s, token_id: id.to_s, log_index: log_idx, trace_index: -1,
                        created_at: Time.current, updated_at: Time.current }
        when weth_deposit
          next if topics.size < 2
          to = "0x#{topics[1][-40..]}" rescue nil
          amount = data.to_i(16)
          transfers << { tx_hash: tx_hash, block_number: block_number, chain_id: chain_id,
                        transfer_type: 'erc20', token_address: address,
                        from_address: '0x0000000000000000000000000000000000000000', to_address: to&.downcase,
                        amount: amount.to_s, token_id: nil, log_index: log_idx, trace_index: -1,
                        created_at: Time.current, updated_at: Time.current }
        when weth_withdrawal
          next if topics.size < 2
          from = "0x#{topics[1][-40..]}" rescue nil
          amount = data.to_i(16)
          transfers << { tx_hash: tx_hash, block_number: block_number, chain_id: chain_id,
                        transfer_type: 'erc20', token_address: address,
                        from_address: from&.downcase, to_address: '0x0000000000000000000000000000000000000000',
                        amount: amount.to_s, token_id: nil, log_index: log_idx, trace_index: -1,
                        created_at: Time.current, updated_at: Time.current }
        end
      end

      if transfers.any?
        AssetTransfer.upsert_all(transfers, unique_by: %i[chain_id tx_hash transfer_type log_index trace_index])
      end

      token_addresses = transfers.filter_map { |t| t[:token_address] }.uniq

      { count: transfers.size, token_addresses: token_addresses }
    end
  end
end
