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
      Temporalio::Activity::Context.current.heartbeat('rpc_fetch')
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
      Temporalio::Activity::Context.current.heartbeat('db_store')
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

      # 4. Decode asset transfers via plugin decoders
      Temporalio::Activity::Context.current.heartbeat('decode_transfers')
      transfers = TransferDecoder.decode(
        chain_id: chain_id,
        block_number: block_num,
        transactions: block_data['transactions'] || [],
        logs: logs,
        withdrawals: block_data['withdrawals'] || []
      )
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

      # 6. Detect arbitrage opportunities from DEX swaps
      arb_count = 0
      if transfers[:swap_count].to_i >= 2
        arbs = ArbDetector.analyze_swaps(
          chain_id: chain_id,
          block_number: block_num,
          swaps: transfers[:swaps]
        )
        arb_count = arbs.size
      end

      Rails.logger.info(
        "Indexed block ##{block_num} on chain #{chain_id}: " \
        "#{tx_records.size} txs, #{log_records.size} logs, #{transfers[:count]} transfers, " \
        "#{transfers[:swap_count]} swaps, #{arb_count} arb opportunities"
      )

      # Return only summary (tiny payload)
      {
        'block_number' => block_num,
        'chain_id' => chain_id,
        'tx_count' => tx_records.size,
        'log_count' => log_records.size,
        'transfer_count' => transfers[:count],
        'swap_count' => transfers[:swap_count],
        'arb_count' => arb_count,
        'token_addresses_count' => token_addresses.size
      }
    end

    # Transfer decoding is now handled by TransferDecoder service (app/services/transfer_decoder.rb)
    # with plugin decoders in app/services/decoders/
  end
end
