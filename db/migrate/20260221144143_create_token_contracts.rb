# frozen_string_literal: true

class CreateTokenContracts < ActiveRecord::Migration[8.1]
  def change
    create_table :token_contracts do |t|
      t.string :address, limit: 42, null: false
      t.integer :chain_id, null: false
      t.string :standard
      t.string :name
      t.string :symbol
      t.integer :decimals
      t.decimal :total_supply, precision: 78, scale: 0

      t.timestamps
    end

    add_index :token_contracts, %i[chain_id address], unique: true
  end
end
