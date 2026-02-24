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

      # POST /api/v1/webhooks/dispatcher/start
      def start_dispatcher
        workflow_id = 'webhook-dispatcher'
        begin
          handle = TemporalClient.connection.workflow_handle(workflow_id)
          handle.describe
          return render json: { error: 'Dispatcher already running' }, status: :conflict
        rescue StandardError
          # Not running, good to start
        end

        handle = TemporalClient.connection.start_workflow(
          Indexer::WebhookDispatcherWorkflow,
          { 'poll_interval' => params.fetch(:poll_interval, 2).to_i },
          id: workflow_id,
          task_queue: ENV.fetch('TEMPORAL_TASK_QUEUE', 'evm-indexer')
        )

        render json: { status: 'started', workflow_id: handle.id }
      end

      # POST /api/v1/webhooks/dispatcher/stop
      def stop_dispatcher
        workflow_id = 'webhook-dispatcher'
        begin
          handle = TemporalClient.connection.workflow_handle(workflow_id)
          handle.cancel
          render json: { status: 'stopped' }
        rescue StandardError
          render json: { error: 'Dispatcher not running' }, status: :not_found
        end
      end

      # GET /api/v1/webhooks/dispatcher/status
      def dispatcher_status
        workflow_id = 'webhook-dispatcher'
        begin
          handle = TemporalClient.connection.workflow_handle(workflow_id)
          desc = handle.describe
          pending = WebhookDelivery.pending.count
          retryable = WebhookDelivery.retryable.count
          unprocessed = AssetTransfer.where(webhook_processed: false).count

          render json: {
            status: desc.status.to_s,
            workflow_id: workflow_id,
            pending_deliveries: pending,
            retryable_deliveries: retryable,
            unprocessed_transfers: unprocessed,
            total_subscriptions: AddressSubscription.active.count
          }
        rescue StandardError
          render json: {
            status: 'not_running',
            pending_deliveries: WebhookDelivery.pending.count,
            unprocessed_transfers: AssetTransfer.where(webhook_processed: false).count,
            total_subscriptions: AddressSubscription.active.count
          }
        end
      end
    end
  end
end
