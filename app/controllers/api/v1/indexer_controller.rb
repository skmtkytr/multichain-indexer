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
        latest_block = case chain_config.chain_type
                       when 'utxo'
                         tip = rpc.get_block_count
                         [tip - (chain_config.confirmation_blocks || 6), 0].max
                       when 'substrate'
                         chain_config.block_tag == 'finalized' ? rpc.get_finalized_block_number : rpc.get_block_number
                       else
                         rpc.get_block_number(tag: chain_config.block_tag || 'finalized') || rpc.get_block_number
                       end

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
            'blocks_per_batch' => chain_config.blocks_per_batch,
            'catchup_parallel_batches' => chain_config.catchup_parallel_batches
          },
          id: "evm-indexer-chain-#{chain_id}",
          task_queue: chain_config.task_queue
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
        chain_config = ChainConfig.find_by(chain_id: chain_id)

        # Get latest block from RPC if chain is configured
        latest_block = nil
        if chain_config&.evm? && chain_config&.enabled?
          begin
            rpc = EthereumRpc.new(chain_id: chain_id)
            latest_block = rpc.get_block_number
          rescue StandardError => e
            Rails.logger.warn("Failed to get latest block for chain #{chain_id}: #{e.message}")
          end
        end

        current_block = cursor&.last_indexed_block || 0

        # Collect RPC rate limiter stats for this chain's endpoints
        rpc_stats = {}
        if chain_config
          urls = chain_config.rpc_url_list
          urls.each do |url|
            s = RpcRateLimiter.stats(url)
            next unless s
            # Aggregate across endpoints
            rpc_stats[:requests_per_second] = (rpc_stats[:requests_per_second] || 0) + s[:rate]
            rpc_stats[:throttled_count] = (rpc_stats[:throttled_count] || 0) + s[:throttled_count]
            rpc_stats[:total_requests] = (rpc_stats[:total_requests] || 0) + s[:total_requests]
          end
        end

        stats = {
          chain_id: chain_id,
          status: cursor&.status || 'not_initialized',
          current_block: current_block,
          latest_block: latest_block,
          gap: latest_block ? latest_block - current_block : nil,
          error: cursor&.error_message,
          blocks_count: IndexedBlock.by_chain(chain_id).count,
          transactions_count: IndexedTransaction.by_chain(chain_id).count,
          logs_count: IndexedLog.by_chain(chain_id).count,
          rpc_stats: rpc_stats.presence
        }

        render json: stats
      end

      # POST /api/v1/webhooks/dispatcher/start
      def start_dispatcher
        workflow_id = 'webhook-dispatcher'
        begin
          handle = TemporalClient.connection.workflow_handle(workflow_id)
          desc = handle.describe
          # status 1 = RUNNING, 2 = CONTINUED_AS_NEW — anything else is not active
          if [1, 2].include?(desc.status)
            return render json: { error: 'Dispatcher already running' }, status: :conflict
          end
        rescue StandardError
          # Not found, good to start
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

          status_label = [1, 2].include?(desc.status) ? 'running' : 'stopped'
          render json: {
            status: status_label,
            workflow_id: workflow_id,
            pending_deliveries: pending,
            retryable_deliveries: retryable,
            total_subscriptions: AddressSubscription.active.count
          }
        rescue StandardError
          render json: {
            status: 'not_running',
            pending_deliveries: WebhookDelivery.pending.count,
            total_subscriptions: AddressSubscription.active.count
          }
        end
      end
    end
  end
end
