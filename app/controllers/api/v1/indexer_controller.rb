module Api
  module V1
    class IndexerController < ApplicationController
      def start
        chain_id = params.fetch(:chain_id, 1).to_i
        start_block = params[:start_block]

        chain_config = ChainConfig.find_by(chain_id: chain_id)
        return render json: { error: "Chain #{chain_id} not configured. Add it first." }, status: :not_found unless chain_config
        return render json: { error: "Chain #{chain_id} is disabled" }, status: :unprocessable_entity unless chain_config.enabled?

        cursor = IndexerCursor.find_or_create_by!(chain_id: chain_id)
        return render json: { error: "Already running" }, status: :conflict if cursor.running?

        # Determine start block
        rpc = EthereumRpc.new(chain_id: chain_id)
        if start_block.present?
          from_block = start_block == "latest" ? rpc.get_block_number : start_block.to_i
        else
          from_block = cursor.last_indexed_block.positive? ? cursor.last_indexed_block + 1 : rpc.get_block_number
        end

        # Start Temporal workflow with chain-specific settings
        handle = TemporalClient.connection.start_workflow(
          Indexer::BlockPollerWorkflow,
          {
            "chain_id" => chain_id,
            "start_block" => from_block,
            "poll_interval_seconds" => chain_config.poll_interval_seconds,
            "blocks_per_batch" => chain_config.blocks_per_batch
          },
          id: "evm-indexer-chain-#{chain_id}",
          task_queue: ENV.fetch("TEMPORAL_TASK_QUEUE", "evm-indexer")
        )

        cursor.mark_running!

        render json: {
          status: "started",
          chain_id: chain_id,
          start_block: from_block,
          workflow_id: handle.id
        }
      end

      def stop
        chain_id = params.fetch(:chain_id, 1).to_i
        cursor = IndexerCursor.find_by(chain_id: chain_id)

        return render json: { error: "Not found" }, status: :not_found unless cursor

        begin
          handle = TemporalClient.connection.workflow_handle("evm-indexer-chain-#{chain_id}")
          handle.cancel
        rescue => e
          Rails.logger.warn("Failed to cancel workflow: #{e.message}")
        end

        cursor.mark_stopped!

        render json: { status: "stopped", chain_id: chain_id }
      end

      def status
        chain_id = params.fetch(:chain_id, 1).to_i
        cursor = IndexerCursor.find_by(chain_id: chain_id)

        stats = {
          chain_id: chain_id,
          status: cursor&.status || "not_initialized",
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
