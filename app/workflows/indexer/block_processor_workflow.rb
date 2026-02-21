require "temporalio/workflow"

module Indexer
  # Processes a single block: fetches data, stores block/txs/logs.
  class BlockProcessorWorkflow < Temporalio::Workflow::Definition
    ACTIVITY_TIMEOUT = 60

    def execute(params)
      chain_id = params["chain_id"] || params[:chain_id]
      block_number = params["block_number"] || params[:block_number]

      retry_policy = Temporalio::RetryPolicy.new(
        maximum_attempts: 5,
        initial_interval: 1,
        backoff_coefficient: 2.0
      )

      # 1. Fetch block data from chain
      block_data = Temporalio::Workflow.execute_activity(
        Indexer::FetchBlockActivity,
        { "action" => "fetch_block", "chain_id" => chain_id, "block_number" => block_number },
        schedule_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: retry_policy
      )

      return if block_data.nil?

      # 2. Process and store block
      Temporalio::Workflow.execute_activity(
        Indexer::ProcessBlockActivity,
        { "action" => "process", "block_data" => block_data },
        schedule_to_close_timeout: ACTIVITY_TIMEOUT
      )

      # 3. Process each transaction
      transactions = block_data["transactions"] || []
      transactions.each do |tx_data|
        Temporalio::Workflow.execute_activity(
          Indexer::ProcessTransactionActivity,
          { "chain_id" => chain_id, "tx_data" => tx_data },
          schedule_to_close_timeout: ACTIVITY_TIMEOUT,
          retry_policy: retry_policy
        )
      end

      # 4. Fetch and process logs for the block
      Temporalio::Workflow.execute_activity(
        Indexer::ProcessLogActivity,
        { "chain_id" => chain_id, "block_number" => block_number },
        schedule_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: retry_policy
      )

      # 5. Update cursor
      Temporalio::Workflow.execute_activity(
        Indexer::ProcessBlockActivity,
        { "action" => "update_cursor", "chain_id" => chain_id, "block_number" => block_number },
        schedule_to_close_timeout: 10
      )
    end
  end
end
