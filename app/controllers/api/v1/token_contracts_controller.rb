# frozen_string_literal: true

module Api
  module V1
    class TokenContractsController < ApplicationController
      def index
        tokens = TokenContract.order(created_at: :desc)
        tokens = tokens.where(chain_id: params[:chain_id]) if params[:chain_id]
        tokens = tokens.where(standard: params[:standard]) if params[:standard]
        tokens = tokens.where("name ILIKE :q OR symbol ILIKE :q", q: "%#{params[:q]}%") if params[:q]
        tokens = tokens.limit(params.fetch(:limit, 50).to_i.clamp(1, 200))

        render json: tokens
      end

      def show
        token = TokenContract.find(params[:id])
        render json: token
      end
    end
  end
end
