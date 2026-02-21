module Indexer
  # Processes a single block: fetches data, stores block/txs/logs.
  class BlockProcessorWorkflow < Temporalio::Workflow
    ACTIVITY_TIMEOUT = 60 # seconds

    def execute(chain_id:, block_number:)
      # 1. Fetch block data from chain
      block_data = workflow.execute_activity(
        Activities::FetchBlockActivity,
        :fetch_block,
        args: [chain_id, block_number],
        start_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: Temporalio::RetryPolicy.new(
          maximum_attempts: 5,
          initial_interval: 1,
          backoff_coefficient: 2.0
        )
      )

      return if block_data.nil?

      # 2. Process and store block
      workflow.execute_activity(
        Activities::ProcessBlockActivity,
        :process,
        args: [block_data],
        start_to_close_timeout: ACTIVITY_TIMEOUT
      )

      # 3. Process each transaction
      transactions = block_data["transactions"] || []
      transactions.each do |tx_data|
        workflow.execute_activity(
          Activities::ProcessTransactionActivity,
          :process,
          args: [chain_id, tx_data],
          start_to_close_timeout: ACTIVITY_TIMEOUT
        )
      end

      # 4. Fetch and process logs for the block
      workflow.execute_activity(
        Activities::ProcessLogActivity,
        :process_block_logs,
        args: [chain_id, block_number],
        start_to_close_timeout: ACTIVITY_TIMEOUT
      )

      # 5. Update cursor
      workflow.execute_activity(
        Activities::ProcessBlockActivity,
        :update_cursor,
        args: [chain_id, block_number],
        start_to_close_timeout: 10
      )
    end
  end
end
