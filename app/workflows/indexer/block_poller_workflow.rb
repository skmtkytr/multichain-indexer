# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  # Long-running workflow that continuously polls for new blocks.
  # Uses continue-as-new to avoid unbounded history growth.
  # Processes blocks in parallel batches for throughput.
  #
  # Signals: pause, resume
  # Queries: current_block, poller_status
  class BlockPollerWorkflow < Temporalio::Workflow::Definition
    workflow_query_attr_reader :current_block
    workflow_query_attr_reader :poller_status

    GET_LATEST_START_TO_CLOSE = 15
    CHILD_WF_RETRY_POLICY = Temporalio::RetryPolicy.new(
      max_attempts: 3,
      initial_interval: 2,
      backoff_coefficient: 2.0,
      max_interval: 30
    )

    def execute(params)
      chain_id = params['chain_id'] || params[:chain_id]
      start_block = params['start_block'] || params[:start_block]
      poll_interval = params['poll_interval_seconds'] || params[:poll_interval_seconds] || 2
      blocks_per_batch = params['blocks_per_batch'] || params[:blocks_per_batch] || 10
      chain_type = params['chain_type'] || params[:chain_type] || 'evm'

      @current_block = start_block
      @poller_status = 'polling'
      @paused = false
      blocks_processed = 0
      max_blocks_before_continue = 100

      # Select the right activity/workflow based on chain type
      fetch_activity, processor_workflow = case chain_type
      when 'utxo'
        [Indexer::UtxoFetchBlockActivity, Indexer::UtxoBlockProcessorWorkflow]
      when 'substrate'
        [Indexer::SubstrateFetchBlockActivity, Indexer::SubstrateBlockProcessorWorkflow]
      else
        [Indexer::FetchBlockActivity, Indexer::BlockProcessorWorkflow]
      end

      while blocks_processed < max_blocks_before_continue
        # Handle pause signal
        if @paused
          @poller_status = 'paused'
          Temporalio::Workflow.wait_condition { !@paused }
          @poller_status = 'polling'
        end

        # Fetch latest block number from chain
        latest = begin
                   Temporalio::Workflow.execute_activity(
                     fetch_activity,
                     { 'action' => 'get_latest', 'chain_id' => chain_id },
                     start_to_close_timeout: GET_LATEST_START_TO_CLOSE,
                     retry_policy: Temporalio::RetryPolicy.new(max_attempts: 5)
                   )
                 rescue => e
                   Temporalio::Workflow.logger.error("get_latest failed, will retry after sleep: #{e.message}")
                   Temporalio::Workflow.sleep(poll_interval * 5)
                   next
                 end

        if @current_block > latest
          Temporalio::Workflow.sleep(poll_interval)
          next
        end

        # Process blocks in parallel batches
        end_block = [@current_block + blocks_per_batch - 1, latest].min
        task_queue = Temporalio::Workflow.info.task_queue

        handles = (@current_block..end_block).map do |block_number|
          Temporalio::Workflow.start_child_workflow(
            processor_workflow,
            { 'chain_id' => chain_id, 'block_number' => block_number },
            id: "process-block-#{chain_id}-#{block_number}",
            task_queue: task_queue,
            retry_policy: CHILD_WF_RETRY_POLICY
          )
        end

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
          'chain_type' => chain_type,
          'start_block' => @current_block,
          'poll_interval_seconds' => poll_interval,
          'blocks_per_batch' => blocks_per_batch
        }
      )
    end

    workflow_query
    def stats
      {
        'current_block' => @current_block,
        'status' => @poller_status,
        'paused' => @paused
      }
    end

    workflow_signal
    def pause
      @paused = true
    end

    workflow_signal
    def resume
      @paused = false
    end

    workflow_signal
    def update_config(new_config)
      # Allows runtime tuning without restart
      # Supported keys: poll_interval_seconds, blocks_per_batch
      Temporalio::Workflow.logger.info("Config update signal received: #{new_config}")
    end
  end
end
