# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  # Long-running workflow that continuously polls for new blocks.
  # Uses continue-as-new to avoid unbounded history growth.
  # Processes blocks in parallel batches for throughput.
  class BlockPollerWorkflow < Temporalio::Workflow::Definition
    workflow_query_attr_reader :current_block
    workflow_query_attr_reader :poller_status

    def execute(params)
      chain_id = params['chain_id'] || params[:chain_id]
      start_block = params['start_block'] || params[:start_block]
      poll_interval = params['poll_interval_seconds'] || params[:poll_interval_seconds] || 2
      blocks_per_batch = params['blocks_per_batch'] || params[:blocks_per_batch] || 10

      @current_block = start_block
      @poller_status = 'polling'
      blocks_processed = 0
      max_blocks_before_continue = 100

      while blocks_processed < max_blocks_before_continue
        # Fetch latest block number from chain
        latest = Temporalio::Workflow.execute_activity(
          Indexer::FetchBlockActivity,
          { 'action' => 'get_latest', 'chain_id' => chain_id },
          schedule_to_close_timeout: 30,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 5)
        )

        if @current_block > latest
          Temporalio::Workflow.sleep(poll_interval)
          next
        end

        # Process blocks in parallel batches
        end_block = [@current_block + blocks_per_batch - 1, latest].min
        task_queue = ENV.fetch('TEMPORAL_TASK_QUEUE', 'evm-indexer')

        # Start all child workflows concurrently
        handles = (@current_block..end_block).map do |block_number|
          Temporalio::Workflow.start_child_workflow(
            Indexer::BlockProcessorWorkflow,
            { 'chain_id' => chain_id, 'block_number' => block_number },
            id: "process-block-#{chain_id}-#{block_number}",
            task_queue: task_queue
          )
        end

        # Wait for all to complete (tolerate individual block failures)
        handles.each do |handle|
          begin
            handle.result
          rescue => e
            Temporalio::Workflow.logger.error("Child workflow failed: #{e.message}")
          end
        end

        batch_size = end_block - @current_block + 1
        blocks_processed += batch_size
        @current_block = end_block + 1
      end

      # Continue-as-new to prevent history from growing unbounded
      @poller_status = 'continuing'
      raise Temporalio::Workflow::ContinueAsNewError.new(
        {
          'chain_id' => chain_id,
          'start_block' => @current_block,
          'poll_interval_seconds' => poll_interval,
          'blocks_per_batch' => blocks_per_batch
        }
      )
    end

    workflow_signal
    def pause
      @poller_status = 'paused'
    end
  end
end
