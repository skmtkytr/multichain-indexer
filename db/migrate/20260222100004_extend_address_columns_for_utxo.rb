# frozen_string_literal: true

class ExtendAddressColumnsForUtxo < ActiveRecord::Migration[8.0]
  def change
    # Bitcoin bech32/taproot addresses can be up to 62 chars (bc1p...)
    # EVM addresses are 42 chars (0x...)
    # Use 128 to be safe for any future format
    change_column :asset_transfers, :from_address, :string, limit: 128
    change_column :asset_transfers, :to_address, :string, limit: 128
    change_column :asset_transfers, :token_address, :string, limit: 128
    change_column :indexed_blocks, :miner, :string, limit: 128
    change_column :indexed_transactions, :from_address, :string, limit: 128
    change_column :indexed_transactions, :to_address, :string, limit: 128
    change_column :indexed_transactions, :contract_address, :string, limit: 128
  end
end
