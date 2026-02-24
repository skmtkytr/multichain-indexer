# frozen_string_literal: true

class CreateWebhookDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_deliveries do |t|
      t.references :address_subscription, null: false, foreign_key: true
      t.references :asset_transfer, null: false, foreign_key: true
      t.string :status, default: 'pending', null: false # pending, sent, failed, exhausted
      t.integer :response_code
      t.text :response_body
      t.integer :attempts, default: 0, null: false
      t.integer :max_attempts, default: 8, null: false # 8 attempts ≈ ~4h with exp backoff
      t.datetime :next_retry_at
      t.datetime :sent_at
      t.timestamps
    end

    add_index :webhook_deliveries, :status
    add_index :webhook_deliveries, :next_retry_at
    add_index :webhook_deliveries, [:address_subscription_id, :asset_transfer_id],
              unique: true, name: 'idx_webhook_deliveries_sub_transfer_uniq'
  end
end
