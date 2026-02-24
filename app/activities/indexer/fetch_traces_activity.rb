# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  class FetchTracesActivity < Temporalio::Activity::Definition
    def execute(params)
      chain_id = params['chain_id']
      block_number_hex = params['block_number_hex']

      chain_config = ChainConfig.find_by(chain_id: chain_id)

      # Skip unless explicitly enabled (supports_trace must be true)
      unless chain_config&.supports_trace
        return { 'traces' => [], 'supported' => false }
      end

      rpc = EthereumRpc.new(chain_id: chain_id)
      Temporalio::Activity::Context.current.heartbeat('trace_fetch')
      traces = rpc.trace_block(block_number_hex, chain_config.trace_method.presence)
      { 'traces' => traces, 'supported' => true }
    rescue StandardError => e
      Rails.logger.warn("Trace fetch failed for chain #{chain_id}: #{e.message}")
      # Disable trace for this chain to avoid repeated failures
      ChainConfig.where(chain_id: chain_id).update_all(supports_trace: false, trace_method: nil)
      { 'traces' => [], 'supported' => false }
    end
  end
end
