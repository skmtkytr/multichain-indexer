# frozen_string_literal: true

class CreateChainConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :chain_configs do |t|
      t.integer :chain_id, null: false
      t.string  :name,               null: false
      t.string  :rpc_url,            null: false
      t.string  :rpc_url_fallback
      t.string  :explorer_url
      t.string  :native_currency,    default: 'ETH'
      t.integer :block_time_ms,      default: 12_000 # avg block time
      t.integer :poll_interval_seconds, default: 2
      t.integer :blocks_per_batch,   default: 10
      t.integer :max_rpc_batch_size, default: 100 # for future batch RPC
      t.boolean :enabled,            default: true
      t.timestamps
    end

    add_index :chain_configs, :chain_id, unique: true
  end
end
