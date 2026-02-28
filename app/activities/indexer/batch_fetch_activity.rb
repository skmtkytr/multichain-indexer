# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  # Catch-up mode activity: processes multiple blocks in a single activity execution.
  #
  # Pipeline architecture for maximum throughput:
  #   1. RPC fetches run in parallel threads (CONCURRENCY workers)
  #   2. DB writes + decoding run sequentially (preserves ordering, avoids contention)
  #   3. Thread pool pre-fetches next blocks while current block is being stored
  #
  # Key differences from Live mode:
  #   - No trace fetching (internal txs) — speed over completeness
  #   - No token metadata enqueue — backfill later
  #   - Single activity = N blocks (no child WF overhead)
  #   - Parallel RPC, sequential DB writes
  #
  # Returns: { 'blocks_processed' => N, 'last_block' => M }
  class BatchFetchActivity < Temporalio::Activity::Definition

    CONCURRENCY = 5  # parallel RPC fetch threads

    def execute(params)
      chain_id = params['chain_id']
      chain_type = params['chain_type'] || 'evm'
      from_block = params['from_block']
      to_block = params['to_block']

      if chain_type != 'evm'
        return execute_sequential(params)
      end

      execute_pipeline(chain_id, from_block, to_block)
    end

    private

    # ── Pipeline mode (EVM only) ──────────────────────────────────────
    def execute_pipeline(chain_id, from_block, to_block)
      config = ChainConfig.find_by(chain_id: chain_id)
      supports_receipts = config&.supports_block_receipts != false

      # Phase 1: Parallel RPC fetch all blocks
      Temporalio::Activity::Context.current.heartbeat({ 'phase' => 'rpc_fetch', 'blocks' => to_block - from_block + 1 })

      blocks = (from_block..to_block).to_a

      # Use thread pool for parallel RPC fetch
      fetched = {}
      mutex = Mutex.new
      fetch_error = nil

      threads = blocks.each_slice((blocks.size / CONCURRENCY.to_f).ceil).map do |chunk|
        Thread.new do
          rpc = EthereumRpc.new(chain_id: chain_id)
          chunk.each do |block_number|
            break if mutex.synchronize { fetch_error }
            begin
              data = rpc.fetch_full_block(block_number, supports_block_receipts: supports_receipts)
              mutex.synchronize { fetched[block_number] = data }
            rescue => e
              mutex.synchronize { fetch_error ||= { block: block_number, error: e.message } }
              break
            end
          end
        end
      end
      threads.each(&:join)

      if fetch_error
        Rails.logger.error("Pipeline RPC fetch failed at block #{fetch_error[:block]} on chain #{chain_id}: #{fetch_error[:error]}")
      end

      # Phase 2: Sequential DB store + decode (in order)
      Temporalio::Activity::Context.current.heartbeat({ 'phase' => 'db_store' })
      processed = 0
      processor = FetchBlockActivity.new

      blocks.each do |block_number|
        full_data = fetched[block_number]
        break unless full_data  # stop at first missing block

        Temporalio::Activity::Context.current.heartbeat({ 'block' => block_number, 'processed' => processed })

        begin
          store_and_decode(processor, chain_id, block_number, full_data, config)
          IndexerCursor.find_or_create_by!(chain_id: chain_id).advance!(block_number)
          processed += 1
        rescue => e
          Rails.logger.error("Pipeline store failed at block #{block_number} on chain #{chain_id}: #{e.message}")
          return {
            'blocks_processed' => processed,
            'last_block' => processed > 0 ? block_number - 1 : from_block - 1,
            'error' => e.message
          }
        end
      end

      {
        'blocks_processed' => processed,
        'last_block' => processed > 0 ? from_block + processed - 1 : from_block - 1
      }
    end

    # Store pre-fetched block data + decode transfers
    def store_and_decode(processor, chain_id, block_number, full_data, config)
      block_data = full_data['block']
      receipts = full_data['receipts'] || []
      logs = full_data['logs'] || []

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

      # DB write (single transaction)
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

      # Decode transfers (skip token metadata enqueue in catch-up)
      transfers = TransferDecoder.decode(
        chain_id: chain_id,
        block_number: block_num,
        transactions: block_data['transactions'] || [],
        logs: logs,
        withdrawals: block_data['withdrawals'] || []
      )

      # Arb detection
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
    end

    # ── Sequential fallback (UTXO / Substrate) ────────────────────────
    def execute_sequential(params)
      chain_id = params['chain_id']
      chain_type = params['chain_type'] || 'evm'
      from_block = params['from_block']
      to_block = params['to_block']

      processor = case chain_type
                  when 'utxo'      then UtxoFetchBlockActivity.new
                  when 'substrate' then SubstrateFetchBlockActivity.new
                  else FetchBlockActivity.new
                  end

      processed = 0
      (from_block..to_block).each do |block_number|
        Temporalio::Activity::Context.current.heartbeat({ 'block' => block_number, 'processed' => processed })
        begin
          processor.send(:fetch_and_store, { 'chain_id' => chain_id, 'block_number' => block_number })
          IndexerCursor.find_or_create_by!(chain_id: chain_id).advance!(block_number)
          processed += 1
        rescue => e
          Rails.logger.error("Batch fetch failed at block #{block_number} on chain #{chain_id}: #{e.message}")
          return {
            'blocks_processed' => processed,
            'last_block' => processed > 0 ? block_number - 1 : from_block - 1,
            'error' => e.message
          }
        end
      end

      { 'blocks_processed' => processed, 'last_block' => to_block }
    end
  end
end
