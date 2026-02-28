# frozen_string_literal: true

module Api
  module V1
    class DexPoolsController < ApplicationController
      def index
        pools = DexPool.order(id: :desc)
        pools = pools.where(chain_id: params[:chain_id]) if params[:chain_id].present?
        pools = pools.where(dex_name: params[:dex_name]) if params[:dex_name].present?

        if params[:token].present?
          t = params[:token].downcase
          pools = pools.where('token0_address = ? OR token1_address = ?', t, t)
        end

        pools = pools.limit(params.fetch(:limit, 50).to_i.clamp(1, 200))
        render json: pools
      end
    end
  end
end
