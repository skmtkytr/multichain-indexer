# frozen_string_literal: true

class CreateIndexedTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :indexed_transactions do |t|
      t.string   :tx_hash,       null: false, limit: 66
      t.bigint   :block_number,  null: false
      t.integer  :tx_index,      null: false
      t.string   :from_address,  null: false, limit: 42
      t.string   :to_address,    limit: 42 # nil for contract creation
      t.decimal  :value,         precision: 78, scale: 0, default: 0
      t.bigint   :gas_used
      t.bigint   :gas_price
      t.bigint   :max_fee_per_gas
      t.bigint   :max_priority_fee_per_gas
      t.text     :input_data
      t.integer  :status # 0=fail, 1=success
      t.string   :contract_address, limit: 42 # created contract
      t.integer  :chain_id,      null: false, default: 1
      t.jsonb    :extra_data,    default: {}
      t.timestamps
    end

    add_index :indexed_transactions, %i[chain_id tx_hash], unique: true
    add_index :indexed_transactions, %i[chain_id block_number]
    add_index :indexed_transactions, :from_address
    add_index :indexed_transactions, :to_address
    add_index :indexed_transactions, :contract_address, where: 'contract_address IS NOT NULL'
  end
end
