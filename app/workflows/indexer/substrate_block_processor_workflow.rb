# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  class SubstrateBlockProcessorWorkflow < Temporalio::Workflow::Definition
    ACTIVITY_TIMEOUT = 120

    def execute(params)
      chain_id = params['chain_id'] || params[:chain_id]
      block_number = params['block_number'] || params[:block_number]

      retry_policy = Temporalio::RetryPolicy.new(
        max_attempts: 5,
        initial_interval: 1,
        backoff_coefficient: 2.0
      )

      result = Temporalio::Workflow.execute_activity(
        Indexer::SubstrateFetchBlockActivity,
        { 'action' => 'fetch_and_store', 'chain_id' => chain_id, 'block_number' => block_number },
        schedule_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: retry_policy
      )

      return if result.nil?

      # Update cursor
      Temporalio::Workflow.execute_activity(
        Indexer::ProcessBlockActivity,
        { 'action' => 'update_cursor', 'chain_id' => chain_id, 'block_number' => block_number },
        schedule_to_close_timeout: 10
      )
    end
  end
end
