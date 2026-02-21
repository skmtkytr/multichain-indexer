require "temporalio/activity"

module Indexer
  class FetchBlockActivity < Temporalio::Activity::Definition
    def execute(params)
      action = params["action"]
      chain_id = params["chain_id"]

      case action
      when "get_latest"
        rpc = EthereumRpc.new(chain_id: chain_id)
        rpc.get_block_number
      when "fetch_block"
        block_number = params["block_number"]
        rpc = EthereumRpc.new(chain_id: chain_id)
        block_data = rpc.get_block_by_number(block_number, full_transactions: true)

        if block_data.nil?
          Rails.logger.warn("Block #{block_number} not found on chain #{chain_id}")
          return nil
        end

        block_data.merge("chain_id" => chain_id)
      end
    end
  end
end
