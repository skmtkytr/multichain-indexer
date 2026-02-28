# frozen_string_literal: true

module Api
  module V1
    class DexSwapsController < ApplicationController
      def index
        swaps = DexSwap.order(id: :desc)
        swaps = swaps.where(chain_id: params[:chain_id]) if params[:chain_id].present?
        swaps = swaps.where(pool_address: params[:pool_address].downcase) if params[:pool_address].present?
        swaps = swaps.where(block_number: params[:block_number]) if params[:block_number].present?

        if params[:token].present?
          t = params[:token].downcase
          swaps = swaps.where('token_in = ? OR token_out = ?', t, t)
        end

        swaps = swaps.limit(params.fetch(:limit, 50).to_i.clamp(1, 200))
        render json: swaps
      end
    end
  end
end
