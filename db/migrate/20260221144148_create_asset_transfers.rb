# frozen_string_literal: true

class CreateAssetTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_transfers do |t|
      t.string :tx_hash, null: false
      t.integer :block_number, null: false
      t.integer :chain_id, null: false
      t.string :transfer_type, null: false
      t.string :token_address, limit: 42 # nullable for native transfers
      t.string :from_address, limit: 42
      t.string :to_address, limit: 42
      t.decimal :amount, precision: 78, scale: 0, null: false
      t.decimal :token_id, precision: 78, scale: 0 # nullable, for NFTs
      t.integer :log_index, default: -1 # -1 for non-log transfers (native/internal)
      t.integer :trace_index, default: -1 # -1 for non-trace transfers

      t.timestamps
    end

    # Main indexes for performance
    add_index :asset_transfers, %i[chain_id block_number]
    add_index :asset_transfers, %i[chain_id tx_hash]
    add_index :asset_transfers, :from_address
    add_index :asset_transfers, :to_address
    add_index :asset_transfers, %i[token_address chain_id]

    # Unique constraint to prevent duplicates
    add_index :asset_transfers, %i[chain_id tx_hash transfer_type log_index trace_index],
              unique: true, name: 'idx_asset_transfers_unique'
  end
end
