# frozen_string_literal: true

class AddChainTypeToChainConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :chain_configs, :chain_type, :string, default: 'evm', null: false
    # rpc_url nullable for UTXO chains that use rpc_endpoints exclusively
    change_column_null :chain_configs, :rpc_url, true
  end
end
