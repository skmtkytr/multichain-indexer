# frozen_string_literal: true

class CreateIndexedBlocks < ActiveRecord::Migration[8.0]
  def change
    create_table :indexed_blocks do |t|
      t.bigint   :number,        null: false
      t.string   :block_hash,    null: false, limit: 66
      t.string   :parent_hash,   null: false, limit: 66
      t.bigint   :timestamp,     null: false
      t.string   :miner,         limit: 42
      t.bigint   :gas_used
      t.bigint   :gas_limit
      t.bigint   :base_fee_per_gas
      t.integer  :transaction_count, default: 0
      t.integer  :chain_id,      null: false, default: 1
      t.jsonb    :extra_data,    default: {}
      t.timestamps
    end

    add_index :indexed_blocks, %i[chain_id number], unique: true
    add_index :indexed_blocks, :block_hash, unique: true
    add_index :indexed_blocks, :timestamp
  end
end
