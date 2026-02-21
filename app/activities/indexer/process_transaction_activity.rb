require "temporalio/activity"

module Indexer
  class ProcessTransactionActivity < Temporalio::Activity::Definition
    def execute(params)
      chain_id = params["chain_id"]
      tx_data = params["tx_data"]

      rpc = EthereumRpc.new(chain_id: chain_id)
      receipt = rpc.get_transaction_receipt(tx_data["hash"])

      IndexedTransaction.upsert(
        {
          tx_hash: tx_data["hash"],
          block_number: tx_data["blockNumber"].to_i(16),
          tx_index: tx_data["transactionIndex"].to_i(16),
          from_address: tx_data["from"]&.downcase,
          to_address: tx_data["to"]&.downcase,
          value: tx_data["value"].to_i(16),
          gas_price: tx_data["gasPrice"]&.to_i(16),
          max_fee_per_gas: tx_data["maxFeePerGas"]&.to_i(16),
          max_priority_fee_per_gas: tx_data["maxPriorityFeePerGas"]&.to_i(16),
          gas_used: receipt&.dig("gasUsed")&.to_i(16),
          input_data: tx_data["input"],
          status: receipt&.dig("status")&.to_i(16),
          contract_address: receipt&.dig("contractAddress")&.downcase,
          chain_id: chain_id,
          created_at: Time.current,
          updated_at: Time.current
        },
        unique_by: [:chain_id, :tx_hash]
      )
    end
  end
end
