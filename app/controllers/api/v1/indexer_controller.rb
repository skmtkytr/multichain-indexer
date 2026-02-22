# frozen_string_literal: true

module Api
  module V1
    class IndexerController < ApplicationController
      def start
        chain_id = params.fetch(:chain_id, 1).to_i
        start_block = params[:start_block]

        chain_config = ChainConfig.find_by(chain_id: chain_id)
        unless chain_config
          return render json: { error: "Chain #{chain_id} not configured. Add it first." },
                        status: :not_found
        end
        unless chain_config.enabled?
          return render json: { error: "Chain #{chain_id} is disabled" },
                        status: :unprocessable_entity
        end

        cursor = IndexerCursor.find_or_create_by!(chain_id: chain_id)
        return render json: { error: 'Already running' }, status: :conflict if cursor.running?

        # Determine start block using the appropriate RPC client
        rpc = case chain_config.chain_type
              when 'utxo' then BitcoinRpc.new(chain_id: chain_id)
              when 'substrate' then SubstrateRpc.new(chain_id: chain_id)
              else EthereumRpc.new(chain_id: chain_id)
              end
        latest_block = chain_config.utxo? ? rpc.get_block_count : rpc.get_block_number

        from_block = if start_block.present?
                       start_block == 'latest' ? latest_block : start_block.to_i
                     else
                       cursor.last_indexed_block.positive? ? cursor.last_indexed_block + 1 : latest_block
                     end

        # Start Temporal workflow with chain-specific settings
        handle = TemporalClient.connection.start_workflow(
          Indexer::BlockPollerWorkflow,
          {
            'chain_id' => chain_id,
            'chain_type' => chain_config.chain_type,
            'start_block' => from_block,
            'poll_interval_seconds' => chain_config.poll_interval_seconds,
            'blocks_per_batch' => chain_config.blocks_per_batch
          },
          id: "evm-indexer-chain-#{chain_id}",
          task_queue: ENV.fetch('TEMPORAL_TASK_QUEUE', 'evm-indexer')
        )

        cursor.mark_running!

        render json: {
          status: 'started',
          chain_id: chain_id,
          start_block: from_block,
          workflow_id: handle.id
        }
      end

      def stop
        chain_id = params.fetch(:chain_id, 1).to_i
        cursor = IndexerCursor.find_by(chain_id: chain_id)

        return render json: { error: 'Not found' }, status: :not_found unless cursor

        begin
          handle = TemporalClient.connection.workflow_handle("evm-indexer-chain-#{chain_id}")
          handle.cancel
        rescue StandardError => e
          Rails.logger.warn("Failed to cancel workflow: #{e.message}")
        end

        cursor.mark_stopped!

        render json: { status: 'stopped', chain_id: chain_id }
      end

      def status
        chain_id = params.fetch(:chain_id, 1).to_i
        cursor = IndexerCursor.find_by(chain_id: chain_id)

        stats = {
          chain_id: chain_id,
          status: cursor&.status || 'not_initialized',
          last_indexed_block: cursor&.last_indexed_block || 0,
          error: cursor&.error_message,
          blocks_count: IndexedBlock.by_chain(chain_id).count,
          transactions_count: IndexedTransaction.by_chain(chain_id).count,
          logs_count: IndexedLog.by_chain(chain_id).count
        }

        render json: stats
      end
    end
  end
end
