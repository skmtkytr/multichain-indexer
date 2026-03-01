# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_01_030000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "address_subscriptions", force: :cascade do |t|
    t.string "address", null: false
    t.bigint "chain_id"
    t.datetime "created_at", null: false
    t.string "direction", default: "both", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "failure_count", default: 0, null: false
    t.string "label"
    t.datetime "last_notified_at"
    t.integer "max_failures", default: 10, null: false
    t.string "secret", null: false
    t.jsonb "transfer_types"
    t.datetime "updated_at", null: false
    t.string "webhook_url", null: false
    t.index ["address", "chain_id"], name: "index_address_subscriptions_on_address_and_chain_id"
    t.index ["address"], name: "index_address_subscriptions_on_address"
    t.index ["enabled"], name: "index_address_subscriptions_on_enabled"
  end

  create_table "arb_opportunities", force: :cascade do |t|
    t.string "arb_type", null: false
    t.integer "block_number", null: false
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.string "dex_buy"
    t.string "dex_sell"
    t.decimal "estimated_profit_wei", precision: 78
    t.string "pool_buy", limit: 42, null: false
    t.string "pool_sell", limit: 42, null: false
    t.decimal "price_buy", precision: 38, scale: 18
    t.decimal "price_sell", precision: 38, scale: 18
    t.decimal "spread_bps", precision: 10, scale: 2
    t.string "token_bridge", limit: 42
    t.string "token_in", limit: 42, null: false
    t.string "tx_hash_buy"
    t.string "tx_hash_sell"
    t.datetime "updated_at", null: false
    t.index ["chain_id", "block_number"], name: "idx_arb_block"
    t.index ["chain_id", "spread_bps"], name: "idx_arb_spread"
    t.index ["created_at"], name: "idx_arb_created"
  end

  create_table "asset_transfers", force: :cascade do |t|
    t.decimal "amount", precision: 78, null: false
    t.integer "block_number", null: false
    t.integer "chain_id", null: false
    t.boolean "confidential", default: false
    t.datetime "created_at", null: false
    t.string "from_address", limit: 128
    t.integer "log_index", default: -1
    t.string "privacy_protocol"
    t.string "to_address", limit: 128
    t.string "token_address", limit: 128
    t.decimal "token_id", precision: 78
    t.integer "trace_index", default: -1
    t.string "transfer_type", null: false
    t.string "tx_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["chain_id", "block_number"], name: "index_asset_transfers_on_chain_id_and_block_number"
    t.index ["chain_id", "tx_hash", "transfer_type", "log_index", "trace_index"], name: "idx_asset_transfers_unique", unique: true
    t.index ["chain_id", "tx_hash"], name: "index_asset_transfers_on_chain_id_and_tx_hash"
    t.index ["from_address"], name: "index_asset_transfers_on_from_address"
    t.index ["to_address"], name: "index_asset_transfers_on_to_address"
    t.index ["token_address", "chain_id"], name: "index_asset_transfers_on_token_address_and_chain_id"
  end

  create_table "chain_configs", force: :cascade do |t|
    t.string "block_tag", default: "finalized", null: false
    t.integer "block_time_ms", default: 12000
    t.integer "blocks_per_batch", default: 10
    t.integer "catchup_parallel_batches", default: 3, null: false
    t.integer "chain_id", null: false
    t.string "chain_type", default: "evm", null: false
    t.integer "confirmation_blocks", default: 0, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true
    t.string "explorer_url"
    t.integer "max_rpc_batch_size", default: 100
    t.string "name", null: false
    t.string "native_currency", default: "ETH"
    t.string "network_type", default: "mainnet", null: false
    t.integer "poll_interval_seconds", default: 2
    t.jsonb "rpc_endpoints", default: []
    t.string "rpc_url"
    t.string "rpc_url_fallback"
    t.string "sidecar_url"
    t.boolean "supports_block_receipts", default: true, null: false
    t.boolean "supports_trace", default: false
    t.string "trace_method"
    t.datetime "updated_at", null: false
    t.index ["chain_id"], name: "index_chain_configs_on_chain_id", unique: true
  end

  create_table "dex_pools", force: :cascade do |t|
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.string "dex_name", null: false
    t.integer "fee_tier"
    t.string "pool_address", limit: 42, null: false
    t.string "token0_address", limit: 42, null: false
    t.integer "token0_decimals"
    t.string "token0_symbol"
    t.string "token1_address", limit: 42, null: false
    t.integer "token1_decimals"
    t.string "token1_symbol"
    t.datetime "updated_at", null: false
    t.index ["chain_id", "pool_address"], name: "index_dex_pools_on_chain_id_and_pool_address", unique: true
    t.index ["chain_id", "token0_address", "token1_address"], name: "idx_dex_pools_pair"
  end

  create_table "dex_swaps", force: :cascade do |t|
    t.decimal "amount_in", precision: 78, null: false
    t.decimal "amount_out", precision: 78, null: false
    t.integer "block_number", null: false
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.string "dex_name"
    t.integer "log_index", null: false
    t.string "pool_address", limit: 42, null: false
    t.decimal "price", precision: 78
    t.string "recipient", limit: 42
    t.string "sender", limit: 42
    t.decimal "sqrt_price_x96", precision: 78
    t.integer "tick"
    t.string "token_in", limit: 42
    t.string "token_out", limit: 42
    t.string "tx_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["chain_id", "block_number"], name: "idx_dex_swaps_block"
    t.index ["chain_id", "pool_address", "block_number"], name: "idx_dex_swaps_pool_block"
    t.index ["chain_id", "token_in", "token_out", "block_number"], name: "idx_dex_swaps_pair_block"
    t.index ["chain_id", "tx_hash", "log_index"], name: "idx_dex_swaps_unique", unique: true
  end

  create_table "event_signatures", force: :cascade do |t|
    t.jsonb "abi_json"
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.string "full_signature", null: false
    t.string "signature_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["signature_hash"], name: "index_event_signatures_on_signature_hash", unique: true
  end

  create_table "indexed_blocks", force: :cascade do |t|
    t.decimal "base_fee_per_gas", precision: 78
    t.string "block_hash", limit: 66, null: false
    t.integer "chain_id", default: 1, null: false
    t.datetime "created_at", null: false
    t.jsonb "extra_data", default: {}
    t.decimal "gas_limit", precision: 78
    t.decimal "gas_used", precision: 78
    t.string "miner", limit: 128
    t.bigint "number", null: false
    t.string "parent_hash", limit: 66, null: false
    t.bigint "timestamp", null: false
    t.integer "transaction_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["block_hash"], name: "index_indexed_blocks_on_block_hash", unique: true
    t.index ["chain_id", "number"], name: "index_indexed_blocks_on_chain_id_and_number", unique: true
    t.index ["timestamp"], name: "index_indexed_blocks_on_timestamp"
  end

  create_table "indexed_logs", force: :cascade do |t|
    t.string "address", limit: 42, null: false
    t.bigint "block_number", null: false
    t.integer "chain_id", default: 1, null: false
    t.datetime "created_at", null: false
    t.text "data"
    t.integer "log_index", null: false
    t.boolean "removed", default: false
    t.string "topic0", limit: 66
    t.string "topic1", limit: 66
    t.string "topic2", limit: 66
    t.string "topic3", limit: 66
    t.string "tx_hash", limit: 66, null: false
    t.datetime "updated_at", null: false
    t.index ["address", "topic0"], name: "index_indexed_logs_on_address_and_topic0"
    t.index ["chain_id", "address"], name: "index_indexed_logs_on_chain_id_and_address"
    t.index ["chain_id", "block_number", "log_index"], name: "index_indexed_logs_on_chain_id_and_block_number_and_log_index", unique: true
    t.index ["topic0"], name: "index_indexed_logs_on_topic0"
    t.index ["tx_hash"], name: "index_indexed_logs_on_tx_hash"
  end

  create_table "indexed_transactions", force: :cascade do |t|
    t.bigint "block_number", null: false
    t.integer "chain_id", default: 1, null: false
    t.string "contract_address", limit: 128
    t.datetime "created_at", null: false
    t.jsonb "extra_data", default: {}
    t.string "from_address", limit: 128, null: false
    t.decimal "gas_price", precision: 78
    t.decimal "gas_used", precision: 78
    t.text "input_data"
    t.decimal "max_fee_per_gas", precision: 78
    t.decimal "max_priority_fee_per_gas", precision: 78
    t.integer "status"
    t.string "to_address", limit: 128
    t.string "tx_hash", limit: 66, null: false
    t.integer "tx_index", null: false
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 78, default: "0"
    t.index ["chain_id", "block_number"], name: "index_indexed_transactions_on_chain_id_and_block_number"
    t.index ["chain_id", "tx_hash"], name: "index_indexed_transactions_on_chain_id_and_tx_hash", unique: true
    t.index ["contract_address"], name: "index_indexed_transactions_on_contract_address", where: "(contract_address IS NOT NULL)"
    t.index ["from_address"], name: "index_indexed_transactions_on_from_address"
    t.index ["to_address"], name: "index_indexed_transactions_on_to_address"
  end

  create_table "indexer_cursors", force: :cascade do |t|
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "last_indexed_block", default: 0, null: false
    t.string "status", default: "stopped", null: false
    t.datetime "updated_at", null: false
    t.index ["chain_id"], name: "index_indexer_cursors_on_chain_id", unique: true
  end

  create_table "substrate_events", force: :cascade do |t|
    t.bigint "block_number", null: false
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}
    t.integer "event_index", null: false
    t.integer "extrinsic_index"
    t.string "method", null: false
    t.string "pallet", null: false
    t.datetime "updated_at", null: false
    t.index ["chain_id", "block_number", "event_index"], name: "idx_sub_evt_unique", unique: true
    t.index ["chain_id", "block_number", "extrinsic_index"], name: "idx_sub_evt_ext"
    t.index ["chain_id", "pallet", "method"], name: "idx_sub_evt_pallet"
  end

  create_table "substrate_extrinsics", force: :cascade do |t|
    t.jsonb "args", default: {}
    t.bigint "block_number", null: false
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.string "extrinsic_hash"
    t.integer "extrinsic_index", null: false
    t.decimal "fee", precision: 30
    t.string "method", null: false
    t.string "pallet", null: false
    t.string "signer", limit: 128
    t.boolean "success", default: true
    t.decimal "tip", precision: 30, default: "0"
    t.datetime "updated_at", null: false
    t.index ["chain_id", "block_number", "extrinsic_index"], name: "idx_sub_ext_unique", unique: true
    t.index ["chain_id", "pallet", "method"], name: "idx_sub_ext_pallet"
    t.index ["extrinsic_hash"], name: "index_substrate_extrinsics_on_extrinsic_hash"
    t.index ["signer"], name: "index_substrate_extrinsics_on_signer"
  end

  create_table "token_contracts", force: :cascade do |t|
    t.string "address", limit: 42, null: false
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.integer "decimals"
    t.string "name"
    t.string "standard"
    t.string "symbol"
    t.decimal "total_supply", precision: 78
    t.datetime "updated_at", null: false
    t.index ["chain_id", "address"], name: "index_token_contracts_on_chain_id_and_address", unique: true
  end

  create_table "utxo_inputs", force: :cascade do |t|
    t.string "address"
    t.decimal "amount", precision: 30
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_coinbase", default: false
    t.string "prev_txid", limit: 64
    t.integer "prev_vout"
    t.text "script_sig"
    t.bigint "sequence"
    t.string "txid", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.integer "vin_index", null: false
    t.jsonb "witness", default: []
    t.index ["address"], name: "index_utxo_inputs_on_address"
    t.index ["chain_id", "prev_txid", "prev_vout"], name: "idx_utxo_inputs_prev_output"
    t.index ["chain_id", "txid", "vin_index"], name: "index_utxo_inputs_on_chain_id_and_txid_and_vin_index", unique: true
  end

  create_table "utxo_outputs", force: :cascade do |t|
    t.string "address"
    t.decimal "amount", precision: 30, null: false
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_confidential", default: false
    t.text "script_pub_key"
    t.string "script_type"
    t.boolean "spent", default: false
    t.string "spent_by_txid", limit: 64
    t.integer "spent_by_vin"
    t.string "txid", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.integer "vout_index", null: false
    t.index ["address"], name: "index_utxo_outputs_on_address"
    t.index ["chain_id", "spent"], name: "idx_utxo_outputs_unspent", where: "(spent = false)"
    t.index ["chain_id", "txid", "vout_index"], name: "index_utxo_outputs_on_chain_id_and_txid_and_vout_index", unique: true
  end

  create_table "utxo_transactions", force: :cascade do |t|
    t.string "block_hash", limit: 64
    t.bigint "block_number", null: false
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.decimal "fee", precision: 30
    t.integer "input_count", default: 0
    t.boolean "is_coinbase", default: false
    t.bigint "lock_time"
    t.integer "output_count", default: 0
    t.integer "size"
    t.string "txid", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.integer "vsize"
    t.index ["chain_id", "block_number"], name: "index_utxo_transactions_on_chain_id_and_block_number"
    t.index ["chain_id", "txid"], name: "index_utxo_transactions_on_chain_id_and_txid", unique: true
  end

  create_table "webhook_deliveries", force: :cascade do |t|
    t.bigint "address_subscription_id", null: false
    t.bigint "asset_transfer_id", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "max_attempts", default: 8, null: false
    t.datetime "next_retry_at"
    t.text "response_body"
    t.integer "response_code"
    t.datetime "sent_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["address_subscription_id", "asset_transfer_id"], name: "idx_webhook_deliveries_sub_transfer_uniq", unique: true
    t.index ["address_subscription_id"], name: "index_webhook_deliveries_on_address_subscription_id"
    t.index ["asset_transfer_id"], name: "index_webhook_deliveries_on_asset_transfer_id"
    t.index ["next_retry_at"], name: "index_webhook_deliveries_on_next_retry_at"
    t.index ["status"], name: "index_webhook_deliveries_on_status"
  end

  add_foreign_key "webhook_deliveries", "address_subscriptions"
  add_foreign_key "webhook_deliveries", "asset_transfers"
end
