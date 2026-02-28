# frozen_string_literal: true

module Api
  module V1
    class ArbOpportunitiesController < ApplicationController
      def index
        arbs = ArbOpportunity.order(id: :desc)
        arbs = arbs.where(chain_id: params[:chain_id]) if params[:chain_id].present?
        arbs = arbs.where(arb_type: params[:arb_type]) if params[:arb_type].present?
        arbs = arbs.where('spread_bps >= ?', params[:min_spread].to_f) if params[:min_spread].present?
        arbs = arbs.where('created_at >= ?', params[:hours].to_i.hours.ago) if params[:hours].present?

        arbs = arbs.limit(params.fetch(:limit, 50).to_i.clamp(1, 200))
        render json: arbs
      end
    end
  end
end
