require "temporalio/activity"

module Indexer
  class ProcessLogActivity < Temporalio::Activity::Definition
    def execute(params)
      chain_id = params["chain_id"]
      block_number = params["block_number"]

      rpc = EthereumRpc.new(chain_id: chain_id)
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

      Temporalio::Activity.logger.info("Indexed #{records.size} logs for block ##{block_number}")
    end
  end
end
