# frozen_string_literal: true

class AddRpcEndpointsToChainConfigs < ActiveRecord::Migration[8.1]
  def change
    # Array of RPC endpoint objects: [{"url": "...", "priority": 1, "label": "chainstack"}, ...]
    add_column :chain_configs, :rpc_endpoints, :jsonb, default: []
  end
end
