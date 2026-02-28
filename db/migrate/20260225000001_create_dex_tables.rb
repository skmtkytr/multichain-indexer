# frozen_string_literal: true

class CreateDexTables < ActiveRecord::Migration[8.1]
  def change
    # DEX pool registry — caches token pair info per pool address
    create_table :dex_pools do |t|
      t.integer :chain_id,        null: false
      t.string  :pool_address,    null: false, limit: 42
      t.string  :dex_name,        null: false                # uniswap_v2, uniswap_v3, sushiswap, curve...
      t.string  :token0_address,  null: false, limit: 42
      t.string  :token1_address,  null: false, limit: 42
      t.string  :token0_symbol
      t.string  :token1_symbol
      t.integer :token0_decimals
      t.integer :token1_decimals
      t.integer :fee_tier                                     # V3 fee in bps (500, 3000, 10000)
      t.timestamps
    end

    add_index :dex_pools, [:chain_id, :pool_address], unique: true
    add_index :dex_pools, [:chain_id, :token0_address, :token1_address], name: 'idx_dex_pools_pair'

    # Individual swap events
    create_table :dex_swaps do |t|
      t.integer :chain_id,        null: false
      t.integer :block_number,    null: false
      t.string  :tx_hash,         null: false
      t.integer :log_index,       null: false
      t.string  :pool_address,    null: false, limit: 42
      t.string  :dex_name                                     # denormalized for fast query
      t.string  :sender,          limit: 42
      t.string  :recipient,       limit: 42
      t.string  :token_in,        limit: 42
      t.string  :token_out,       limit: 42
      t.decimal :amount_in,       precision: 78, null: false
      t.decimal :amount_out,      precision: 78, null: false
      t.decimal :price,           precision: 38, scale: 18    # token_out/token_in ratio (raw)
      t.decimal :sqrt_price_x96,  precision: 78               # V3 sqrtPriceX96 after swap
      t.integer :tick                                         # V3 tick after swap
      t.timestamps
    end

    add_index :dex_swaps, [:chain_id, :tx_hash, :log_index], unique: true, name: 'idx_dex_swaps_unique'
    add_index :dex_swaps, [:chain_id, :block_number], name: 'idx_dex_swaps_block'
    add_index :dex_swaps, [:chain_id, :pool_address, :block_number], name: 'idx_dex_swaps_pool_block'
    add_index :dex_swaps, [:chain_id, :token_in, :token_out, :block_number], name: 'idx_dex_swaps_pair_block'

    # Detected arbitrage opportunities
    create_table :arb_opportunities do |t|
      t.integer :chain_id,           null: false
      t.integer :block_number,       null: false
      t.string  :token_in,           limit: 42, null: false   # start/end token (cycle)
      t.string  :token_bridge,       limit: 42                # middle token in triangular arb
      t.string  :pool_buy,           limit: 42, null: false   # pool with lower price
      t.string  :pool_sell,          limit: 42, null: false   # pool with higher price
      t.string  :dex_buy
      t.string  :dex_sell
      t.decimal :price_buy,          precision: 38, scale: 18
      t.decimal :price_sell,         precision: 38, scale: 18
      t.decimal :spread_bps,         precision: 10, scale: 2  # price diff in basis points
      t.decimal :estimated_profit_wei, precision: 78           # rough profit estimate
      t.string  :arb_type,          null: false                # direct, triangular
      t.string  :tx_hash_buy
      t.string  :tx_hash_sell
      t.timestamps
    end

    add_index :arb_opportunities, [:chain_id, :block_number], name: 'idx_arb_block'
    add_index :arb_opportunities, [:chain_id, :spread_bps], name: 'idx_arb_spread'
    add_index :arb_opportunities, :created_at, name: 'idx_arb_created'
  end
end
