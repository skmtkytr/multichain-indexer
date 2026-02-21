require "temporalio/activity"

module Indexer
  class ProcessBlockActivity < Temporalio::Activity::Definition
    def execute(params)
      action = params["action"]

      case action
      when "process"
        block_data = params["block_data"]
        chain_id = block_data["chain_id"]
        number = block_data["number"].to_i(16)

        IndexedBlock.upsert(
          {
            number: number,
            block_hash: block_data["hash"],
            parent_hash: block_data["parentHash"],
            timestamp: block_data["timestamp"].to_i(16),
            miner: block_data["miner"]&.downcase,
            gas_used: block_data["gasUsed"]&.to_i(16),
            gas_limit: block_data["gasLimit"]&.to_i(16),
            base_fee_per_gas: block_data["baseFeePerGas"]&.to_i(16),
            transaction_count: (block_data["transactions"] || []).size,
            chain_id: chain_id,
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: [:chain_id, :number]
        )

        Temporalio::Activity.logger.info("Indexed block ##{number} on chain #{chain_id}")

      when "update_cursor"
        chain_id = params["chain_id"]
        block_number = params["block_number"]
        cursor = IndexerCursor.find_or_create_by!(chain_id: chain_id)
        cursor.advance!(block_number)
      end
    end
  end
end
