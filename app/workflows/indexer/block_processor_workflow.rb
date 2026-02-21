require "temporalio/workflow"

module Indexer
  # Processes a single block: fetches all data (block + receipts + logs), then stores.
  # Only 2 activities: fetch (RPC) → store (DB), minimizing RPC calls.
  class BlockProcessorWorkflow < Temporalio::Workflow::Definition
    ACTIVITY_TIMEOUT = 120

    def execute(params)
      chain_id = params["chain_id"] || params[:chain_id]
      block_number = params["block_number"] || params[:block_number]

      retry_policy = Temporalio::RetryPolicy.new(
        max_attempts: 5,
        initial_interval: 1,
        backoff_coefficient: 2.0
      )

      # 1. Fetch block + receipts + logs in minimal RPC calls
      full_data = Temporalio::Workflow.execute_activity(
        Indexer::FetchBlockActivity,
        { "action" => "fetch_full_block", "chain_id" => chain_id, "block_number" => block_number },
        schedule_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: retry_policy
      )

      return if full_data.nil?

      # 2. Process and store everything in one DB transaction
      Temporalio::Workflow.execute_activity(
        Indexer::ProcessBlockActivity,
        {
          "action" => "process_full",
          "block_data" => full_data["block"],
          "receipts" => full_data["receipts"],
          "logs" => full_data["logs"]
        },
        schedule_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: retry_policy
      )

      # 3. Update cursor
      Temporalio::Workflow.execute_activity(
        Indexer::ProcessBlockActivity,
        { "action" => "update_cursor", "chain_id" => chain_id, "block_number" => block_number },
        schedule_to_close_timeout: 10
      )
    end
  end
end
