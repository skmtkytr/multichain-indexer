# frozen_string_literal: true

require 'temporalio/workflow'

module Indexer
  # Processes a single block: fetches data from RPC and stores to DB in one activity.
  # All heavy data stays inside the activity — only a small summary returns through Temporal gRPC.
  # This avoids the 4MB gRPC payload limit that Polygon/Arbitrum blocks can exceed.
  class BlockProcessorWorkflow < Temporalio::Workflow::Definition
    FETCH_START_TO_CLOSE = 60       # single RPC+DB attempt
    FETCH_HEARTBEAT_TIMEOUT = 30    # must heartbeat within 30s during long fetches
    TRACE_START_TO_CLOSE = 60
    CURSOR_START_TO_CLOSE = 10

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

      # 1. Fetch from RPC + store to DB + decode transfers
      result = Temporalio::Workflow.execute_activity(
        Indexer::FetchBlockActivity,
        { 'action' => 'fetch_and_store', 'chain_id' => chain_id, 'block_number' => block_number },
        start_to_close_timeout: FETCH_START_TO_CLOSE,
        heartbeat_timeout: FETCH_HEARTBEAT_TIMEOUT,
        retry_policy: retry_policy
      )

      return if result.nil?

      # 2. Fetch traces for internal transactions (best-effort, optional)
      block_number_hex = "0x#{block_number.to_s(16)}"
      begin
        trace_result = Temporalio::Workflow.execute_activity(
          Indexer::FetchTracesActivity,
          { 'chain_id' => chain_id, 'block_number_hex' => block_number_hex },
          start_to_close_timeout: TRACE_START_TO_CLOSE,
          heartbeat_timeout: FETCH_HEARTBEAT_TIMEOUT,
          retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
        )

        if trace_result && trace_result['traces']&.any?
          Temporalio::Workflow.execute_activity(
            Indexer::DecodeTransfersActivity,
            {
              'action' => 'store_internal_transfers',
              'chain_id' => chain_id,
              'block_number' => block_number,
              'traces' => trace_result['traces']
            },
            start_to_close_timeout: FETCH_START_TO_CLOSE,
            heartbeat_timeout: FETCH_HEARTBEAT_TIMEOUT,
            retry_policy: retry_policy
          )
        end
      rescue => e
        Temporalio::Workflow.logger.warn("Trace fetch failed (non-fatal): #{e.message}")
      end

      # 3. Update cursor
      Temporalio::Workflow.execute_activity(
        Indexer::ProcessBlockActivity,
        { 'action' => 'update_cursor', 'chain_id' => chain_id, 'block_number' => block_number },
        start_to_close_timeout: CURSOR_START_TO_CLOSE
      )
    end
  end
end
