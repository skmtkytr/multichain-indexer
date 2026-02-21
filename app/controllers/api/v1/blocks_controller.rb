# frozen_string_literal: true

module Api
  module V1
    class BlocksController < ApplicationController
      def index
        chain_id = params.fetch(:chain_id, 1).to_i
        blocks = IndexedBlock.by_chain(chain_id)
                             .recent
                             .limit(params.fetch(:limit, 25).to_i)
                             .offset(params.fetch(:offset, 0).to_i)

        render json: blocks
      end

      def show
        chain_id = params.fetch(:chain_id, 1).to_i
        block = IndexedBlock.by_chain(chain_id).find_by!(number: params[:number])
        render json: block, include: :indexed_transactions
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Block not found' }, status: :not_found
      end
    end
  end
end
