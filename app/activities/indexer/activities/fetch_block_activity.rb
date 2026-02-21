module Indexer
  module Activities
    class FetchBlockActivity < Temporalio::Activity
      def get_latest_block_number(chain_id)
        rpc = EthereumRpc.new
        rpc.get_block_number
      end

      def fetch_block(chain_id, block_number)
        rpc = EthereumRpc.new
        block_data = rpc.get_block_by_number(block_number, full_transactions: true)

        if block_data.nil?
          activity.logger.warn("Block #{block_number} not found on chain #{chain_id}")
          return nil
        end

        block_data.merge("chain_id" => chain_id)
      end
    end
  end
end
