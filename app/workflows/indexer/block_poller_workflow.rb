# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  # Long-running workflow that continuously polls for new blocks.
  # Uses continue-as-new to avoid unbounded history growth.
  #
  # 2-Mode Architecture:
  #   - Catch-up mode: when behind by > CATCHUP_THRESHOLD blocks, uses BatchFetchActivity
  #     (single activity processes N blocks in a loop, no child WFs, max throughput)
  #   - Live mode: when caught up, uses child workflows per block
  #     (full processing: traces, token metadata, parallel batches)
  #
  # Signals: pause, resume
  # Queries: current_block, poller_status, stats
  class BlockPollerWorkflow < Temporalio::Workflow::Definition
    workflow_query_attr_reader :current_block
    workflow_query_attr_reader :poller_status

    GET_LATEST_START_TO_CLOSE = 15
    CATCHUP_THRESHOLD = 50           # switch to catch-up if behind by this many blocks
    CATCHUP_BATCH_SIZE = 50          # blocks per BatchFetchActivity call
    CATCHUP_CHILD_TIMEOUT = 360      # 6 min per batch child workflow
    DEFAULT_CATCHUP_PARALLEL = 3     # default parallel batches in catch-up mode

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
      catchup_parallel = params['catchup_parallel_batches'] || params[:catchup_parallel_batches] || DEFAULT_CATCHUP_PARALLEL

      @current_block = start_block
      @poller_status = 'initializing'
      @paused = false
      blocks_processed = 0
      max_blocks_before_continue = 500  # higher for catch-up mode efficiency

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
          @poller_status = 'live_waiting'
          Temporalio::Workflow.sleep(poll_interval)
          next
        end

        gap = latest - @current_block

        if gap > CATCHUP_THRESHOLD
          # ══════════════════════════════════════════════════
          # CATCH-UP MODE: parallel batch processing, max throughput
          # ══════════════════════════════════════════════════
          @poller_status = "catchup (#{gap} behind, #{catchup_parallel}x parallel)"

          # Build up to catchup_parallel batch ranges
          batch_ranges = []
          batch_cursor = @current_block
          catchup_parallel.times do
            break if batch_cursor > latest
            batch_end = [batch_cursor + CATCHUP_BATCH_SIZE - 1, latest].min
            batch_ranges << { 'from' => batch_cursor, 'to' => batch_end }
            batch_cursor = batch_end + 1
          end

          retry_policy = Temporalio::RetryPolicy.new(
            max_attempts: 3,
            initial_interval: 5,
            backoff_coefficient: 2.0,
            max_interval: 60
          )

          # Launch all batches in parallel via child workflows
          task_queue = Temporalio::Workflow.info.task_queue
          handles = batch_ranges.map do |range|
            Temporalio::Workflow.start_child_workflow(
              Indexer::BatchProcessorWorkflow,
              {
                'chain_id' => chain_id,
                'chain_type' => chain_type,
                'from_block' => range['from'],
                'to_block' => range['to']
              },
              id: "catchup-batch-#{chain_id}-#{range['from']}-#{range['to']}",
              task_queue: task_queue,
              retry_policy: retry_policy
            )
          end

          # Collect results in order — stop at first failed batch
          all_ok = true
          handles.each_with_index do |handle, idx|
            begin
              result = handle.result
              actual_processed = result['blocks_processed'] || 0
              if actual_processed > 0
                @current_block = (result['last_block'] || @current_block) + 1
                blocks_processed += actual_processed
              end
              if result['error']
                all_ok = false
                break
              end
            rescue => e
              Temporalio::Workflow.logger.error("Catch-up batch #{idx} failed: #{e.message}")
              all_ok = false
              break
            end
          end

          unless all_ok
            Temporalio::Workflow.sleep(poll_interval * 3)
          end

        else
          # ══════════════════════════════════════════════════
          # LIVE MODE: child workflows, full processing
          # ══════════════════════════════════════════════════
          @poller_status = 'live'

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
      end

      # Continue-as-new to prevent history from growing unbounded.
      # Update the cursor before continue-as-new so the watchdog can recover
      # if the new execution fails to start.
      @poller_status = 'continuing'

      # Signal that we're about to continue — the watchdog will pick up
      # from last_indexed_block if the new execution doesn't start.
      begin
        Temporalio::Workflow.execute_activity(
          Indexer::ProcessBlockActivity,
          { 'action' => 'update_cursor', 'chain_id' => chain_id, 'block_number' => @current_block - 1 },
          start_to_close_timeout: 10,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
        )
      rescue => e
        Temporalio::Workflow.logger.warn("Failed to update cursor before continue-as-new: #{e.message}")
      end

      raise Temporalio::Workflow::ContinueAsNewError.new(
        {
          'chain_id' => chain_id,
          'chain_type' => chain_type,
          'start_block' => @current_block,
          'poll_interval_seconds' => poll_interval,
          'blocks_per_batch' => blocks_per_batch,
          'catchup_parallel_batches' => catchup_parallel
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
      Temporalio::Workflow.logger.info("Config update signal received: #{new_config}")
    end
  end
end
