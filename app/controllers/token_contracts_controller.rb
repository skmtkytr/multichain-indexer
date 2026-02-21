# frozen_string_literal: true

class TokenContractsController < ApplicationController
  def index
    @tokens = TokenContract.all.order(:name)

    @tokens = @tokens.by_chain(params[:chain_id]) if params[:chain_id].present?
    @tokens = @tokens.by_standard(params[:standard]) if params[:standard].present?
    @tokens = @tokens.limit(params[:limit]&.to_i || 100)

    render json: @tokens.map { |token| format_token(token) }
  end

  def show
    @token = TokenContract.find(params[:id])
    render json: format_token(@token)
  end

  private

  def format_token(token)
    {
      id: token.id,
      address: token.address,
      chain_id: token.chain_id,
      name: token.name,
      symbol: token.symbol,
      decimals: token.decimals,
      standard: token.standard,
      total_supply: token.total_supply&.to_s,
      display_name: token.display_name,
      transfer_count: token.asset_transfers.count,
      created_at: token.created_at
    }
  end
end
