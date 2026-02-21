class CreateIndexerCursors < ActiveRecord::Migration[8.0]
  def change
    create_table :indexer_cursors do |t|
      t.integer :chain_id,          null: false
      t.bigint  :last_indexed_block, null: false, default: 0
      t.string  :status,            null: false, default: "stopped" # running, stopped, error
      t.text    :error_message
      t.timestamps
    end

    add_index :indexer_cursors, :chain_id, unique: true
  end
end
