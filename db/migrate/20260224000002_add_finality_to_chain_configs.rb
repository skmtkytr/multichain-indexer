# frozen_string_literal: true

class AddFinalityToChainConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :chain_configs, :block_tag, :string, default: 'finalized', null: false
    add_column :chain_configs, :confirmation_blocks, :integer, default: 0, null: false
  end
end
