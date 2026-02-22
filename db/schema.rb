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

ActiveRecord::Schema[8.1].define(version: 2026_02_22_100004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.integer "block_time_ms", default: 12000
    t.integer "blocks_per_batch", default: 10
    t.integer "chain_id", null: false
    t.string "chain_type", default: "evm", null: false
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
    t.boolean "supports_block_receipts", default: true, null: false
    t.boolean "supports_trace", default: false
    t.string "trace_method"
    t.datetime "updated_at", null: false
    t.index ["chain_id"], name: "index_chain_configs_on_chain_id", unique: true
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
end
