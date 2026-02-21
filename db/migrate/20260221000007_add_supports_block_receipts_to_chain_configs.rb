class AddSupportsBlockReceiptsToChainConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :chain_configs, :supports_block_receipts, :boolean, default: true, null: false
  end
end
