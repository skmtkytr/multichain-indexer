class CreateIndexedLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :indexed_logs do |t|
      t.string   :tx_hash,       null: false, limit: 66
      t.bigint   :block_number,  null: false
      t.integer  :log_index,     null: false
      t.string   :address,       null: false, limit: 42  # contract address
      t.string   :topic0,        limit: 66  # event signature
      t.string   :topic1,        limit: 66
      t.string   :topic2,        limit: 66
      t.string   :topic3,        limit: 66
      t.text     :data
      t.boolean  :removed,       default: false
      t.integer  :chain_id,      null: false, default: 1
      t.timestamps
    end

    add_index :indexed_logs, [:chain_id, :block_number, :log_index], unique: true
    add_index :indexed_logs, [:chain_id, :address]
    add_index :indexed_logs, :topic0
    add_index :indexed_logs, [:address, :topic0]
    add_index :indexed_logs, :tx_hash
  end
end
