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

      when "fetch_full_block"
        block_number = params["block_number"]
        config = ChainConfig.find_by(chain_id: chain_id)
        supports_receipts = config&.supports_block_receipts != false

        rpc = EthereumRpc.new(chain_id: chain_id)
        result = rpc.fetch_full_block(block_number, supports_block_receipts: supports_receipts)

        if result.nil?
          Rails.logger.warn("Block #{block_number} not found on chain #{chain_id}")
          return nil
        end

        result

      # Legacy: keep backward compat
      when "fetch_block"
        block_number = params["block_number"]
        rpc = EthereumRpc.new(chain_id: chain_id)
        block_data = rpc.get_block_by_number(block_number, full_transactions: true)
        block_data&.merge("chain_id" => chain_id)
      end
    end
  end
end
