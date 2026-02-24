# frozen_string_literal: true

class WebhookDelivery < ApplicationRecord
  belongs_to :address_subscription
  belongs_to :asset_transfer

  scope :pending, -> { where(status: 'pending') }
  scope :retryable, -> { where(status: 'pending').where('next_retry_at IS NULL OR next_retry_at <= ?', Time.current) }
  scope :failed, -> { where(status: 'failed') }

  # Exponential backoff: 10s, 20s, 40s, 80s, 160s, 320s, 640s, 1280s (~21min total)
  def backoff_seconds
    10 * (2**attempts)
  end

  def schedule_retry!
    if attempts >= max_attempts
      update!(status: 'exhausted')
      address_subscription.increment!(:failure_count)
      address_subscription.auto_disable!
    else
      update!(next_retry_at: Time.current + backoff_seconds.seconds)
    end
  end

  def mark_sent!(code, body = nil)
    update!(
      status: 'sent',
      response_code: code,
      response_body: body&.truncate(1000),
      sent_at: Time.current,
      attempts: attempts + 1
    )
    address_subscription.update!(failure_count: 0, last_notified_at: Time.current)
  end

  def mark_failed!(code, body = nil)
    update!(
      response_code: code,
      response_body: body&.truncate(1000),
      attempts: attempts + 1
    )
    schedule_retry!
  end
end
