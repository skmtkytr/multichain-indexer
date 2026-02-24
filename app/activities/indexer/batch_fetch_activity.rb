# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  # Catch-up mode activity: processes multiple blocks in a single activity execution.
  # No child workflows, no Temporal overhead per block — just a tight loop.
  # Sends heartbeat after each block so Temporal knows we're alive.
  #
  # Key differences from Live mode:
  #   - No trace fetching (internal txs) — speed over completeness
  #   - No token metadata enqueue — backfill later
  #   - Single activity = N blocks (no child WF overhead)
  #
  # Returns: { 'blocks_processed' => N, 'last_block' => M }
  class BatchFetchActivity < Temporalio::Activity::Definition

    def execute(params)
      chain_id = params['chain_id']
      chain_type = params['chain_type'] || 'evm'
      from_block = params['from_block']
      to_block = params['to_block']

      # Instantiate the right single-block processor
      processor = case chain_type
                  when 'utxo'    then UtxoFetchBlockActivity.new
                  when 'substrate' then SubstrateFetchBlockActivity.new
                  else FetchBlockActivity.new
                  end

      processed = 0

      (from_block..to_block).each do |block_number|
        # Heartbeat with current progress — also allows Temporal to detect cancellation
        Temporalio::Activity::Context.current.heartbeat(
          { 'block' => block_number, 'processed' => processed }
        )

        begin
          # Reuse existing fetch_and_store logic
          # Heartbeat calls inside will piggyback on our activity context
          processor.send(:fetch_and_store, {
            'chain_id' => chain_id,
            'block_number' => block_number
          })

          # Update cursor after each block (durable progress)
          IndexerCursor.find_or_create_by!(chain_id: chain_id).advance!(block_number)
          processed += 1
        rescue => e
          Rails.logger.error("Batch fetch failed at block #{block_number} on chain #{chain_id}: #{e.message}")
          # Return partial progress — don't lose completed blocks
          return {
            'blocks_processed' => processed,
            'last_block' => processed > 0 ? block_number - 1 : from_block - 1,
            'error' => e.message
          }
        end
      end

      {
        'blocks_processed' => processed,
        'last_block' => to_block
      }
    end
  end
end
