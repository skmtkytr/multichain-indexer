# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  class ProcessBlockActivity < Temporalio::Activity::Definition
    def execute(params)
      action = params['action']

      case action
      when 'process_full'
        process_full(params)
      when 'process'
        process_block_only(params['block_data'])
      when 'update_cursor'
        update_cursor(params['chain_id'], params['block_number'])
      end
    end

    private

    # New: process block + txs + logs in one activity
    def process_full(params)
      block_data = params['block_data']
      receipts = params['receipts'] || []
      logs = params['logs'] || []
      chain_id = block_data['chain_id']
      block_number = block_data['number'].to_i(16)

      # Build receipt lookup by tx hash
      receipt_by_hash = receipts.each_with_object({}) do |r, h|
        h[r['transactionHash']] = r if r
      end

      # Build records outside transaction for logging
      tx_records = (block_data['transactions'] || []).map do |tx_data|
        receipt = receipt_by_hash[tx_data['hash']]
        {
          tx_hash: tx_data['hash'],
          block_number: block_number,
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

      ActiveRecord::Base.transaction do
        IndexedBlock.upsert(
          {
            number: block_number,
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

      Rails.logger.info(
        "Indexed block ##{block_number} on chain #{chain_id}: " \
        "#{tx_records.size} txs, #{log_records.size} logs"
      )
    end

    # Legacy: block only
    def process_block_only(block_data)
      chain_id = block_data['chain_id']
      number = block_data['number'].to_i(16)

      IndexedBlock.upsert(
        {
          number: number,
          block_hash: block_data['hash'],
          parent_hash: block_data['parentHash'],
          timestamp: block_data['timestamp'].to_i(16),
          miner: block_data['miner']&.downcase,
          gas_used: block_data['gasUsed']&.to_i(16),
          gas_limit: block_data['gasLimit']&.to_i(16),
          base_fee_per_gas: block_data['baseFeePerGas']&.to_i(16),
          transaction_count: (block_data['transactions'] || []).size,
          chain_id: chain_id,
          created_at: Time.current,
          updated_at: Time.current
        },
        unique_by: %i[chain_id number]
      )
    end

    def update_cursor(chain_id, block_number)
      cursor = IndexerCursor.find_or_create_by!(chain_id: chain_id)
      cursor.advance!(block_number)
    end
  end
end
