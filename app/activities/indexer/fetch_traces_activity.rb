# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  class FetchTracesActivity < Temporalio::Activity::Definition
    def execute(params)
      chain_id = params['chain_id']
      block_number_hex = params['block_number_hex']

      rpc = EthereumRpc.new(chain_id: chain_id)
      chain_config = ChainConfig.find_by(chain_id: chain_id)

      # Return empty if chain doesn't support tracing
      return { traces: [], supported: false } unless chain_config&.supports_trace

      traces = rpc.trace_block(block_number_hex, chain_config.trace_method)
      { traces: traces, supported: true }
    rescue StandardError => e
      Rails.logger.warn("Trace fetch failed for chain #{chain_id}: #{e.message}")
      # Mark chain as not supporting trace
      ChainConfig.where(chain_id: chain_id).update_all(supports_trace: false)
      { traces: [], supported: false }
    end
  end
end
