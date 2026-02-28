# frozen_string_literal: true

class AddCatchupParallelBatchesToChainConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :chain_configs, :catchup_parallel_batches, :integer, default: 3, null: false
  end
end
