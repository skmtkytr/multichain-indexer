# frozen_string_literal: true

class CreateSubstrateTables < ActiveRecord::Migration[8.0]
  def change
    create_table :substrate_extrinsics do |t|
      t.integer  :chain_id,         null: false
      t.bigint   :block_number,     null: false
      t.integer  :extrinsic_index,  null: false
      t.string   :extrinsic_hash               # nullable (inherents have no hash)
      t.string   :pallet,           null: false  # "balances", "assets", etc.
      t.string   :method,           null: false  # "transferKeepAlive", "transfer"
      t.string   :signer,           limit: 128   # SS58 address, nullable for inherents
      t.jsonb    :args,             default: {}
      t.boolean  :success,          default: true
      t.decimal  :fee,              precision: 30, scale: 0
      t.decimal  :tip,              precision: 30, scale: 0, default: 0
      t.timestamps
    end

    add_index :substrate_extrinsics, %i[chain_id block_number extrinsic_index], unique: true, name: 'idx_sub_ext_unique'
    add_index :substrate_extrinsics, %i[chain_id pallet method], name: 'idx_sub_ext_pallet'
    add_index :substrate_extrinsics, :signer
    add_index :substrate_extrinsics, :extrinsic_hash

    create_table :substrate_events do |t|
      t.integer  :chain_id,         null: false
      t.bigint   :block_number,     null: false
      t.integer  :extrinsic_index              # nullable (system events)
      t.integer  :event_index,      null: false
      t.string   :pallet,           null: false
      t.string   :method,           null: false
      t.jsonb    :data,             default: {}
      t.timestamps
    end

    add_index :substrate_events, %i[chain_id block_number event_index], unique: true, name: 'idx_sub_evt_unique'
    add_index :substrate_events, %i[chain_id pallet method], name: 'idx_sub_evt_pallet'
    add_index :substrate_events, %i[chain_id block_number extrinsic_index], name: 'idx_sub_evt_ext'

    # Extend chain_type to include substrate
    # (column already exists from previous migration, just need to allow 'substrate' value)
  end
end
