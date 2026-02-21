# frozen_string_literal: true

module Api
  module V1
    class AssetTransfersController < ApplicationController
      def index
        transfers = AssetTransfer.order(block_number: :desc, log_index: :asc)
        transfers = transfers.where(chain_id: params[:chain_id]) if params[:chain_id]
        transfers = transfers.where(transfer_type: params[:type]) if params[:type]
        transfers = transfers.where(token_address: params[:token_address]&.downcase) if params[:token_address]
        transfers = transfers.where("from_address = :addr OR to_address = :addr", addr: params[:address]&.downcase) if params[:address]
        transfers = transfers.where(tx_hash: params[:tx_hash]) if params[:tx_hash]
        transfers = transfers.limit(params.fetch(:limit, 50).to_i.clamp(1, 200))

        # Join token metadata for display
        render json: transfers.map { |t| transfer_json(t) }
      end

      def show
        transfer = AssetTransfer.find(params[:id])
        render json: transfer_json(transfer)
      end

      private

      def transfer_json(t)
        token = t.token_contract
        native = t.native? || t.internal?
        {
          id: t.id,
          tx_hash: t.tx_hash,
          block_number: t.block_number,
          chain_id: t.chain_id,
          transfer_type: t.transfer_type,
          token_address: t.token_address,
          token_symbol: native ? "ETH" : (token&.symbol || "Unknown"),
          token_name: native ? "Ether" : (token&.name),
          token_decimals: native ? 18 : token&.decimals,
          from_address: t.from_address,
          to_address: t.to_address,
          amount: t.amount.to_s,
          amount_display: format_amount(t.amount, native ? 18 : token&.decimals),
          token_id: t.token_id&.to_s,
          log_index: t.log_index,
          trace_index: t.trace_index,
          created_at: t.created_at
        }
      end

      def format_amount(amount, decimals)
        return amount.to_s unless decimals && decimals > 0
        divisor = 10**decimals
        whole = amount / divisor
        frac = (amount % divisor).to_s.rjust(decimals, "0").sub(/0+$/, "")
        frac.empty? ? whole.to_s : "#{whole}.#{frac}"
      end
    end
  end
end
