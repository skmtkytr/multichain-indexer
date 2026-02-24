# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  class SubstrateBlockProcessorWorkflow < Temporalio::Workflow::Definition
    FETCH_START_TO_CLOSE = 60
    FETCH_SCHEDULE_TO_CLOSE = 300
    CURSOR_START_TO_CLOSE = 10
    CURSOR_SCHEDULE_TO_CLOSE = 30

    def execute(params)
      chain_id = params['chain_id'] || params[:chain_id]
      block_number = params['block_number'] || params[:block_number]

      retry_policy = Temporalio::RetryPolicy.new(
        max_attempts: 5,
        initial_interval: 1,
        backoff_coefficient: 2.0,
        max_interval: 30,
        non_retryable_error_types: ['NonRetryableError']
      )

      result = Temporalio::Workflow.execute_activity(
        Indexer::SubstrateFetchBlockActivity,
        { 'action' => 'fetch_and_store', 'chain_id' => chain_id, 'block_number' => block_number },
        start_to_close_timeout: FETCH_START_TO_CLOSE,
        schedule_to_close_timeout: FETCH_SCHEDULE_TO_CLOSE,
        retry_policy: retry_policy
      )

      return if result.nil?

      Temporalio::Workflow.execute_activity(
        Indexer::ProcessBlockActivity,
        { 'action' => 'update_cursor', 'chain_id' => chain_id, 'block_number' => block_number },
        start_to_close_timeout: CURSOR_START_TO_CLOSE,
        schedule_to_close_timeout: CURSOR_SCHEDULE_TO_CLOSE
      )
    end
  end
end
