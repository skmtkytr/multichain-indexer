# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  class WebhookDispatcherWorkflow < Temporalio::Workflow::Definition
    workflow_query_attr_reader :dispatcher_status
    workflow_query_attr_reader :iterations_count

    def execute(params = {})
      poll_interval = params['poll_interval'] || 2
      @iterations_count = 0
      @dispatcher_status = 'running'
      @paused = false
      max_iterations = params['max_iterations'] || 500

      loop do
        # Handle pause
        if @paused
          @dispatcher_status = 'paused'
          Temporalio::Workflow.wait_condition { !@paused }
          @dispatcher_status = 'running'
        end

        # 1. Scan new asset_transfers → create webhook_deliveries
        Temporalio::Workflow.execute_activity(
          Indexer::WebhookDispatchActivity,
          'scan_and_enqueue',
          start_to_close_timeout: 30,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
        )

        # 2. Deliver pending webhooks (including retries)
        Temporalio::Workflow.execute_activity(
          Indexer::WebhookDispatchActivity,
          'deliver_pending',
          start_to_close_timeout: 60,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
        )

        @iterations_count += 1

        if @iterations_count >= max_iterations
          @dispatcher_status = 'continuing'
          raise Temporalio::Workflow::ContinueAsNewError.new(
            args: [params]
          )
        end

        Temporalio::Workflow.sleep(poll_interval)
      end
    end

    workflow_signal
    def pause
      @paused = true
    end

    workflow_signal
    def resume
      @paused = false
    end
  end
end
