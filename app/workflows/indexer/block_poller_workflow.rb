module Indexer
  # Long-running workflow that continuously polls for new blocks.
  # Uses continue-as-new to avoid unbounded history growth.
  class BlockPollerWorkflow < Temporalio::Workflow
    workflow_query_attr :current_block
    workflow_query_attr :status

    def execute(chain_id:, start_block:, poll_interval_seconds: 2, blocks_per_batch: 10)
      @current_block = start_block
      @status = "polling"
      blocks_processed = 0
      max_blocks_before_continue = 100 # continue-as-new to keep history small

      while blocks_processed < max_blocks_before_continue
        # Fetch latest block number from chain
        latest = workflow.execute_activity(
          Activities::FetchBlockActivity,
          :get_latest_block_number,
          args: [chain_id],
          start_to_close_timeout: 30
        )

        if @current_block > latest
          # Wait for new blocks
          workflow.sleep(poll_interval_seconds)
          next
        end

        # Process blocks in batches
        end_block = [@current_block + blocks_per_batch - 1, latest].min

        (@current_block..end_block).each do |block_number|
          workflow.execute_child_workflow(
            BlockProcessorWorkflow,
            args: [{ chain_id: chain_id, block_number: block_number }],
            id: "process-block-#{chain_id}-#{block_number}"
          )
          blocks_processed += 1
        end

        @current_block = end_block + 1
      end

      # Continue-as-new to prevent history from growing unbounded
      @status = "continuing"
      workflow.continue_as_new(
        chain_id: chain_id,
        start_block: @current_block,
        poll_interval_seconds: poll_interval_seconds,
        blocks_per_batch: blocks_per_batch
      )
    end
  end
end
