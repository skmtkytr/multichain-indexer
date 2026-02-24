# frozen_string_literal: true

class CreateAddressSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :address_subscriptions do |t|
      t.string :address, null: false
      t.bigint :chain_id, null: true # null = all chains
      t.string :webhook_url, null: false
      t.string :label
      t.jsonb :transfer_types, default: nil # null = all types
      t.string :direction, default: 'both', null: false # both, incoming, outgoing
      t.boolean :enabled, default: true, null: false
      t.string :secret, null: false # HMAC-SHA256 signing secret
      t.integer :failure_count, default: 0, null: false
      t.integer :max_failures, default: 10, null: false
      t.datetime :last_notified_at
      t.timestamps
    end

    add_index :address_subscriptions, :address
    add_index :address_subscriptions, [:address, :chain_id]
    add_index :address_subscriptions, :enabled
  end
end
