# frozen_string_literal: true

class FixIntegerOverflowColumns < ActiveRecord::Migration[8.0]
  def change
    # gas_price and fee fields can exceed bigint range on some chains
    change_column :indexed_transactions, :gas_price, :decimal, precision: 78, scale: 0
    change_column :indexed_transactions, :max_fee_per_gas, :decimal, precision: 78, scale: 0
    change_column :indexed_transactions, :max_priority_fee_per_gas, :decimal, precision: 78, scale: 0
    change_column :indexed_transactions, :gas_used, :decimal, precision: 78, scale: 0

    # block fields too
    change_column :indexed_blocks, :gas_used, :decimal, precision: 78, scale: 0
    change_column :indexed_blocks, :gas_limit, :decimal, precision: 78, scale: 0
    change_column :indexed_blocks, :base_fee_per_gas, :decimal, precision: 78, scale: 0
  end
end
