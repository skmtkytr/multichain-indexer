# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  # Thin child workflow wrapper around BatchFetchActivity.
  # Exists solely to enable parallel catch-up batches via start_child_workflow.
  class BatchProcessorWorkflow < Temporalio::Workflow::Definition
    ACTIVITY_TIMEOUT = 600   # 10 min per batch (rate-limited RPCs need more time)
    HEARTBEAT_TIMEOUT = 30

    def execute(params)
      Temporalio::Workflow.execute_activity(
        Indexer::BatchFetchActivity,
        params,
        start_to_close_timeout: ACTIVITY_TIMEOUT,
        heartbeat_timeout: HEARTBEAT_TIMEOUT,
        retry_policy: Temporalio::RetryPolicy.new(
          max_attempts: 3,
          initial_interval: 5,
          backoff_coefficient: 2.0,
          max_interval: 60
        )
      )
    end
  end
end
