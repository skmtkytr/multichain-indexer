# frozen_string_literal: true

class FixDexPricePrecision < ActiveRecord::Migration[8.1]
  def change
    # price ratio can be extremely large for low-value tokens (e.g. 898120807887574700000)
    # Remove scale constraint to allow arbitrary precision
    change_column :dex_swaps, :price, :decimal, precision: 78, scale: nil
    change_column :arb_opportunities, :price_buy, :decimal, precision: 78, scale: nil
    change_column :arb_opportunities, :price_sell, :decimal, precision: 78, scale: nil
  end
end
