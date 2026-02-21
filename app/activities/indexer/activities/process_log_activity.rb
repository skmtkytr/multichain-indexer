module Indexer
  module Activities
    class ProcessLogActivity < Temporalio::Activity
      def process_block_logs(chain_id, block_number)
        rpc = EthereumRpc.new
        logs = rpc.get_logs(from_block: block_number, to_block: block_number)

        return if logs.nil? || logs.empty?

        records = logs.map do |log|
          topics = log["topics"] || []
          {
            tx_hash: log["transactionHash"],
            block_number: log["blockNumber"].to_i(16),
            log_index: log["logIndex"].to_i(16),
            address: log["address"]&.downcase,
            topic0: topics[0],
            topic1: topics[1],
            topic2: topics[2],
            topic3: topics[3],
            data: log["data"],
            removed: log["removed"] || false,
            chain_id: chain_id,
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        IndexedLog.upsert_all(records, unique_by: [:chain_id, :block_number, :log_index])

        activity.logger.info("Indexed #{records.size} logs for block ##{block_number}")
      end
    end
  end
end
