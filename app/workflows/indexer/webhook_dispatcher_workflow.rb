# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  class WebhookDispatcherWorkflow < Temporalio::Workflow::Definition

    def execute(params = {})
      poll_interval = params['poll_interval'] || 2
      iterations = 0
      max_iterations = params['max_iterations'] || 500 # continue-as-new after this

      loop do
        # 1. Scan new asset_transfers → create webhook_deliveries
        scan_result = Temporalio::Workflow.execute_activity(
          Indexer::WebhookDispatchActivity,
          'scan_and_enqueue',
          start_to_close_timeout: 30,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
        )

        # 2. Deliver pending webhooks (including retries)
        deliver_result = Temporalio::Workflow.execute_activity(
          Indexer::WebhookDispatchActivity,
          'deliver_pending',
          start_to_close_timeout: 60,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
        )

        iterations += 1

        # Continue-as-new to keep history bounded
        if iterations >= max_iterations
          raise Temporalio::Workflow::ContinueAsNewError.new(
            args: [params]
          )
        end

        # Sleep between polls
        Temporalio::Workflow.sleep(poll_interval)
      end
    end
  end
end
