# frozen_string_literal: true

module Api
  module V1
    class SubscriptionsController < ApplicationController
      # GET /api/v1/subscriptions
      def index
        subs = AddressSubscription.order(created_at: :desc)
        subs = subs.where(enabled: true) if params[:active] == 'true'
        subs = subs.where('LOWER(address) = ?', params[:address].downcase) if params[:address].present?
        subs = subs.limit(params.fetch(:limit, 50).to_i)

        render json: subs.map { |s| sub_json(s) }
      end

      # GET /api/v1/subscriptions/:id
      def show
        sub = AddressSubscription.find(params[:id])
        render json: sub_json(sub, detail: true)
      end

      # POST /api/v1/subscriptions
      def create
        sub = AddressSubscription.new(sub_params)
        if sub.save
          render json: sub_json(sub), status: :created
        else
          render json: { errors: sub.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/subscriptions/:id
      def update
        sub = AddressSubscription.find(params[:id])
        if sub.update(sub_params)
          render json: sub_json(sub)
        else
          render json: { errors: sub.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/subscriptions/:id
      def destroy
        sub = AddressSubscription.find(params[:id])
        sub.destroy!
        render json: { status: 'deleted' }
      end

      # POST /api/v1/subscriptions/:id/test
      def test
        sub = AddressSubscription.find(params[:id])
        payload = {
          event: 'test',
          subscription_id: sub.id,
          message: 'Webhook test from multichain-indexer',
          timestamp: Time.current.iso8601
        }.to_json
        signature = OpenSSL::HMAC.hexdigest('SHA256', sub.secret, payload)

        uri = URI.parse(sub.webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.path.presence || '/')
        request['Content-Type'] = 'application/json'
        request['X-Webhook-Signature'] = signature
        request['User-Agent'] = 'multichain-indexer/1.0'
        request.body = payload

        response = http.request(request)
        render json: { status: response.code.to_i.between?(200, 299) ? 'ok' : 'error',
                       response_code: response.code.to_i,
                       response_body: response.body&.truncate(500) }
      rescue StandardError => e
        render json: { status: 'error', error: e.message }, status: :bad_gateway
      end

      # GET /api/v1/subscriptions/:id/deliveries
      def deliveries
        sub = AddressSubscription.find(params[:id])
        dels = sub.webhook_deliveries.order(created_at: :desc).limit(params.fetch(:limit, 50).to_i)
        render json: dels.map { |d|
          {
            id: d.id,
            asset_transfer_id: d.asset_transfer_id,
            status: d.status,
            response_code: d.response_code,
            attempts: d.attempts,
            next_retry_at: d.next_retry_at,
            sent_at: d.sent_at,
            created_at: d.created_at
          }
        }
      end

      private

      def sub_params
        permitted = params.permit(:address, :chain_id, :webhook_url, :label, :direction, :enabled, :max_failures)
        permitted[:transfer_types] = params[:transfer_types] if params[:transfer_types].is_a?(Array)
        permitted
      end

      def sub_json(sub, detail: false)
        json = {
          id: sub.id,
          address: sub.address,
          chain_id: sub.chain_id,
          webhook_url: sub.webhook_url,
          label: sub.label,
          transfer_types: sub.transfer_types,
          direction: sub.direction,
          enabled: sub.enabled,
          failure_count: sub.failure_count,
          max_failures: sub.max_failures,
          last_notified_at: sub.last_notified_at,
          created_at: sub.created_at
        }
        json[:secret] = sub.secret if detail
        json
      end
    end
  end
end
