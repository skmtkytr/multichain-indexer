# frozen_string_literal: true

class UpdateChain1BlocksPerBatch < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      UPDATE chain_configs SET blocks_per_batch = 3 WHERE chain_id = 1
    SQL
  end

  def down
    execute <<-SQL
      UPDATE chain_configs SET blocks_per_batch = 1 WHERE chain_id = 1
    SQL
  end
end
