# frozen_string_literal: true

require 'temporalio/activity'
require 'net/http'
require 'json'
require 'openssl'
require 'uri'

module Indexer
  class WebhookDispatchActivity < Temporalio::Activity::Definition

    def execute(action)
      case action
      when 'scan_and_enqueue'
        scan_and_enqueue
      when 'deliver_pending'
        deliver_pending
      else
        raise "Unknown action: #{action}"
      end
    end

    private

    # Query transfers matching active subscriptions since last delivery
    def scan_and_enqueue
      subs = AddressSubscription.active.to_a
      return { scanned: 0, enqueued: 0 } if subs.empty?

      enqueued = 0

      subs.each do |sub|
        # Find where we left off for this subscription
        last_delivery = WebhookDelivery.where(address_subscription_id: sub.id)
                                       .order(asset_transfer_id: :desc).first
        last_transfer_id = last_delivery&.asset_transfer_id || 0

        addr = sub.address.downcase
        scope = AssetTransfer.where('id > ?', last_transfer_id)
        scope = scope.where(chain_id: sub.chain_id) if sub.chain_id.present?

        scope = case sub.direction
                when 'incoming' then scope.where('LOWER(to_address) = ?', addr)
                when 'outgoing' then scope.where('LOWER(from_address) = ?', addr)
                else scope.where('LOWER(to_address) = ? OR LOWER(from_address) = ?', addr, addr)
                end

        scope = scope.where(transfer_type: sub.transfer_types) if sub.transfer_types.present?

        scope.order(:id).limit(200).each do |transfer|
          WebhookDelivery.find_or_create_by!(
            address_subscription: sub,
            asset_transfer: transfer
          ) { |d| d.status = 'pending' }
          enqueued += 1
        end
      end

      { enqueued: enqueued }
    end

    # Deliver pending/retryable webhook deliveries
    def deliver_pending
      deliveries = WebhookDelivery.retryable
                                  .includes(:address_subscription, :asset_transfer)
                                  .limit(100)
      return { delivered: 0, failed: 0 } if deliveries.empty?

      delivered = 0
      failed = 0

      deliveries.each do |delivery|
        sub = delivery.address_subscription
        next unless sub.enabled?

        begin
          payload = build_payload(delivery)
          signature = sign_payload(payload, sub.secret)

          uri = URI.parse(sub.webhook_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = 5
          http.read_timeout = 10

          request = Net::HTTP::Post.new(uri.path.presence || '/')
          request['Content-Type'] = 'application/json'
          request['X-Webhook-Signature'] = signature
          request['X-Webhook-Id'] = delivery.id.to_s
          request['User-Agent'] = 'multichain-indexer/1.0'
          request.body = payload

          response = http.request(request)

          if response.code.to_i.between?(200, 299)
            delivery.mark_sent!(response.code.to_i, response.body)
            delivered += 1
          else
            delivery.mark_failed!(response.code.to_i, response.body)
            failed += 1
          end
        rescue StandardError => e
          delivery.mark_failed!(0, e.message)
          failed += 1
        end
      end

      { delivered: delivered, failed: failed }
    end

    def build_payload(delivery)
      transfer = delivery.asset_transfer
      chain = ChainConfig.find_by(chain_id: transfer.chain_id)

      {
        event: 'asset_transfer',
        subscription_id: delivery.address_subscription_id,
        delivery_id: delivery.id,
        transfer: {
          id: transfer.id,
          chain_id: transfer.chain_id,
          chain_name: chain&.name,
          block_number: transfer.block_number,
          tx_hash: transfer.tx_hash,
          transfer_type: transfer.transfer_type,
          from_address: transfer.from_address,
          to_address: transfer.to_address,
          amount: transfer.amount,
          token_address: transfer.token_address,
          token_symbol: transfer.token_symbol,
          token_id: transfer.token_id,
          log_index: transfer.log_index
        },
        timestamp: Time.current.iso8601
      }.to_json
    end

    def sign_payload(payload, secret)
      OpenSSL::HMAC.hexdigest('SHA256', secret, payload)
    end
  end
end
