# frozen_string_literal: true

module Api
  module V1
    class TransactionsController < ApplicationController
      def index
        chain_id = params.fetch(:chain_id, 1).to_i
        txs = IndexedTransaction.by_chain(chain_id)

        txs = txs.from_addr(params[:from]) if params[:from].present?
        txs = txs.to_addr(params[:to]) if params[:to].present?
        txs = txs.where(block_number: params[:block_number]) if params[:block_number].present?

        txs = txs.order(block_number: :desc, tx_index: :asc)
                 .limit(params.fetch(:limit, 25).to_i)
                 .offset(params.fetch(:offset, 0).to_i)

        render json: txs
      end

      def show
        chain_id = params.fetch(:chain_id, 1).to_i
        tx = IndexedTransaction.by_chain(chain_id).find_by!(tx_hash: params[:hash])
        render json: tx
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Transaction not found' }, status: :not_found
      end
    end
  end
end
