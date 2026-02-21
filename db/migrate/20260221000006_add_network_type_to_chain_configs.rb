# frozen_string_literal: true

class AddNetworkTypeToChainConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :chain_configs, :network_type, :string, null: false, default: 'mainnet'
    # mainnet, testnet, devnet
  end
end
