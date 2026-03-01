# frozen_string_literal: true

class AddExecutedToArbOpportunities < ActiveRecord::Migration[8.0]
  def change
    add_column :arb_opportunities, :executed, :boolean, default: false, null: false
    add_index :arb_opportunities, :executed
  end
end
