# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/address_transfers?addresses=0xabc,0xdef&chain_id=137
    #
    # Returns asset transfers involving any of the given addresses,
    # with a `direction` field ("in" / "out" / "self") relative to the watched addresses.
    # Useful for monitoring wallets for deposits and withdrawals.
    class AddressTransfersController < ApplicationController
      def index
        raw = params[:addresses].to_s
        addresses = raw.split(",").map { |a| a.strip.downcase }.select { |a| a.match?(/\A0x[0-9a-f]{40}\z/) }

        if addresses.empty?
          return render json: { error: "addresses parameter required (comma-separated)" }, status: :unprocessable_entity
        end

        if addresses.size > 50
          return render json: { error: "max 50 addresses" }, status: :unprocessable_entity
        end

        transfers = AssetTransfer
                      .where("from_address IN (:addrs) OR to_address IN (:addrs)", addrs: addresses)
                      .order(block_number: :desc, log_index: :asc)

        transfers = transfers.where(chain_id: params[:chain_id]) if params[:chain_id].present?
        transfers = transfers.where(transfer_type: params[:type]) if params[:type].present?
        transfers = transfers.where(token_address: params[:token_address]&.downcase) if params[:token_address].present?

        # Block range filter
        transfers = transfers.where("block_number >= ?", params[:from_block].to_i) if params[:from_block].present?
        transfers = transfers.where("block_number <= ?", params[:to_block].to_i) if params[:to_block].present?

        limit = params.fetch(:limit, 100).to_i.clamp(1, 500)
        offset = params.fetch(:offset, 0).to_i
        transfers = transfers.offset(offset).limit(limit)

        address_set = addresses.to_set

        render json: {
          addresses: addresses,
          count: transfers.size,
          transfers: transfers.map { |t| transfer_json(t, address_set) }
        }
      end

      private

      def transfer_json(t, address_set)
        from_watched = address_set.include?(t.from_address)
        to_watched = address_set.include?(t.to_address)

        direction = if from_watched && to_watched
                      "self"
                    elsif to_watched
                      "in"
                    else
                      "out"
                    end

        token = t.token_contract
        native = t.native? || t.internal? || t.withdrawal?
        decimals = native ? 18 : token&.decimals
        native_symbol = ChainConfig.cached_find(t.chain_id)&.native_currency || 'ETH'

        {
          tx_hash: t.tx_hash,
          block_number: t.block_number,
          chain_id: t.chain_id,
          direction: direction,
          transfer_type: t.transfer_type,
          token_address: t.token_address,
          token_symbol: native ? native_symbol : (token&.symbol || "Unknown"),
          token_name: native ? native_symbol : token&.name,
          token_decimals: decimals,
          from_address: t.from_address,
          to_address: t.to_address,
          amount: t.amount.to_s,
          amount_display: format_amount(t.amount, decimals),
          token_id: t.token_id&.to_s,
          log_index: t.log_index,
          trace_index: t.trace_index
        }
      end

      def format_amount(amount, decimals)
        return amount.to_s unless decimals && decimals > 0
        divisor = 10**decimals
        whole = amount / divisor
        frac = (amount % divisor).to_s.rjust(decimals, "0").sub(/0+$/, "")
        frac.empty? ? whole.to_s : "#{whole}.#{frac}"
      rescue
        amount.to_s
      end

      # Removed: chain_native_symbol hardcode — now uses ChainConfig.cached_find
    end
  end
end
