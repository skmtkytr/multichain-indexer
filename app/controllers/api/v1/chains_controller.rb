# frozen_string_literal: true

module Api
  module V1
    class ChainsController < ApplicationController
      def index
        chains = ChainConfig.order(:chain_id).map do |c|
          chain_json(c, mask: true)
        end
        render json: chains
      end

      def show
        chain = ChainConfig.find_by!(chain_id: params[:chain_id])
        render json: chain_json(chain)
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Chain not found' }, status: :not_found
      end

      def create
        chain = ChainConfig.new(chain_params)

        if chain.save
          render json: chain_json(chain), status: :created
        else
          render json: { errors: chain.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        chain = ChainConfig.find_by!(chain_id: params[:chain_id])

        if chain.update(chain_params)
          render json: chain_json(chain)
        else
          render json: { errors: chain.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Chain not found' }, status: :not_found
      end

      def destroy
        chain = ChainConfig.find_by!(chain_id: params[:chain_id])
        cursor = IndexerCursor.find_by(chain_id: chain.chain_id)

        if cursor&.running?
          render json: { error: 'Stop the indexer before removing chain' }, status: :conflict
          return
        end

        chain.destroy!
        render json: { status: 'deleted', chain_id: chain.chain_id }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Chain not found' }, status: :not_found
      end

      # POST /api/v1/chains/:chain_id/test
      def test
        chain = ChainConfig.find_by!(chain_id: params[:chain_id])
        rpc = EthereumRpc.new(chain_id: chain.chain_id)

        started = Time.now
        block_number = rpc.get_block_number
        latency_ms = ((Time.now - started) * 1000).round

        render json: {
          chain_id: chain.chain_id,
          name: chain.name,
          rpc_url: mask_url(chain.rpc_url),
          latest_block: block_number,
          latency_ms: latency_ms,
          status: 'ok'
        }
      rescue StandardError => e
        render json: {
          chain_id: params[:chain_id].to_i,
          status: 'error',
          error: e.message
        }, status: :bad_gateway
      end

      private

      def chain_params
        permitted = params.permit(
          :chain_id, :name, :rpc_url, :chain_type,
          :explorer_url, :native_currency, :block_time_ms,
          :poll_interval_seconds, :blocks_per_batch,
          :max_rpc_batch_size, :enabled, :network_type
        )
        # Accept rpc_endpoints as JSON array
        if params[:rpc_endpoints].is_a?(Array)
          permitted[:rpc_endpoints] = params[:rpc_endpoints].map do |ep|
            ep.permit(:url, :label, :priority).to_h
          end
        end
        permitted
      end

      def chain_json(chain, mask: false)
        {
          chain_id: chain.chain_id,
          name: chain.name,
          chain_type: chain.chain_type,
          network_type: chain.network_type,
          rpc_url: mask ? mask_url(chain.rpc_url) : chain.rpc_url,
          rpc_endpoints: (chain.rpc_endpoints || []).map do |ep|
            { url: mask ? mask_url(ep["url"]) : ep["url"], label: ep["label"], priority: ep["priority"] }
          end,
          explorer_url: chain.explorer_url,
          native_currency: chain.native_currency,
          block_time_ms: chain.block_time_ms,
          poll_interval_seconds: chain.poll_interval_seconds,
          blocks_per_batch: chain.blocks_per_batch,
          enabled: chain.enabled,
          supports_trace: chain.supports_trace,
          trace_method: chain.trace_method,
          status: chain.status,
          last_indexed_block: chain.last_indexed_block
        }
      end

      # Mask API keys in URLs for display
      def mask_url(url)
        uri = URI(url)
        if uri.path.length > 10
          # Likely contains API key in path (Alchemy/Infura style)
          masked_path = "#{uri.path[0..10]}..."
          "#{uri.scheme}://#{uri.host}#{masked_path}"
        else
          url
        end
      rescue StandardError
        url
      end
    end
  end
end
