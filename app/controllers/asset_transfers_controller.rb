# frozen_string_literal: true

class AssetTransfersController < ApplicationController
  def index
    @transfers = AssetTransfer.includes(:token_contract)
                              .recent
                              .limit(params[:limit]&.to_i || 100)

    @transfers = @transfers.by_chain(params[:chain_id]) if params[:chain_id].present?
    @transfers = @transfers.by_block(params[:block_number]) if params[:block_number].present?
    @transfers = @transfers.by_address(params[:address]) if params[:address].present?
    @transfers = @transfers.by_token(params[:token_address]) if params[:token_address].present?
    @transfers = @transfers.where(transfer_type: params[:type]) if params[:type].present?

    render json: @transfers.map { |transfer| format_transfer(transfer) }
  end

  def show
    @transfer = AssetTransfer.find(params[:id])
    render json: format_transfer(@transfer)
  end

  private

  def format_transfer(transfer)
    {
      id: transfer.id,
      tx_hash: transfer.tx_hash,
      block_number: transfer.block_number,
      chain_id: transfer.chain_id,
      transfer_type: transfer.transfer_type,
      token_address: transfer.token_address,
      token_symbol: transfer.token_symbol,
      from_address: transfer.from_address,
      to_address: transfer.to_address,
      amount: transfer.amount.to_s,
      formatted_amount: transfer.formatted_amount,
      token_id: transfer.token_id&.to_s,
      description: transfer.description,
      tx_url: transfer.tx_url,
      log_index: transfer.log_index == -1 ? nil : transfer.log_index,
      trace_index: transfer.trace_index == -1 ? nil : transfer.trace_index,
      created_at: transfer.created_at
    }
  end
end
