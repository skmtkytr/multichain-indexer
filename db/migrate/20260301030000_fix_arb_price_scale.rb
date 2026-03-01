# frozen_string_literal: true

class FixArbPriceScale < ActiveRecord::Migration[8.0]
  def change
    change_column :arb_opportunities, :price_buy, :decimal, precision: 38, scale: 18
    change_column :arb_opportunities, :price_sell, :decimal, precision: 38, scale: 18
  end
end
