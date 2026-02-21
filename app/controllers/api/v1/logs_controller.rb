module Api
  module V1
    class LogsController < ApplicationController
      def index
        chain_id = params.fetch(:chain_id, 1).to_i
        logs = IndexedLog.by_chain(chain_id)

        logs = logs.by_contract(params[:address]) if params[:address].present?
        logs = logs.by_event(params[:topic0]) if params[:topic0].present?
        logs = logs.where(block_number: params[:block_number]) if params[:block_number].present?
        logs = logs.where(tx_hash: params[:tx_hash]) if params[:tx_hash].present?

        logs = logs.order(block_number: :desc, log_index: :asc)
                   .limit(params.fetch(:limit, 25).to_i)
                   .offset(params.fetch(:offset, 0).to_i)

        render json: logs
      end
    end
  end
end
