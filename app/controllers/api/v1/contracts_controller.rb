# frozen_string_literal: true

module Api
  module V1
    class ContractsController < ApplicationController
      def index
        chain_id = params.fetch(:chain_id, 1).to_i
        contracts = IndexedTransaction.by_chain(chain_id)
                                      .contract_creations
                                      .order(block_number: :desc)
                                      .limit(params.fetch(:limit, 25).to_i)
                                      .offset(params.fetch(:offset, 0).to_i)

        render json: contracts.map { |tx|
          {
            contract_address: tx.contract_address,
            creator: tx.from_address,
            tx_hash: tx.tx_hash,
            block_number: tx.block_number,
            created_at: tx.created_at
          }
        }
      end

      def show
        chain_id = params.fetch(:chain_id, 1).to_i
        address = params[:address]&.downcase

        # Find contract creation tx
        creation_tx = IndexedTransaction.by_chain(chain_id)
                                        .find_by(contract_address: address)

        # Find all logs for this contract
        logs_count = IndexedLog.by_chain(chain_id).by_contract(address).count
        recent_logs = IndexedLog.by_chain(chain_id).by_contract(address)
                                .order(block_number: :desc)
                                .limit(20)

        render json: {
          address: address,
          chain_id: chain_id,
          creation_tx: creation_tx&.tx_hash,
          creator: creation_tx&.from_address,
          created_at_block: creation_tx&.block_number,
          total_logs: logs_count,
          recent_logs: recent_logs
        }
      end
    end
  end
end
