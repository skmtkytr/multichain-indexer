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

ActiveRecord::Schema[8.1].define(version: 2026_02_21_000007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "chain_configs", force: :cascade do |t|
    t.integer "block_time_ms", default: 12000
    t.integer "blocks_per_batch", default: 10
    t.integer "chain_id", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true
    t.string "explorer_url"
    t.integer "max_rpc_batch_size", default: 100
    t.string "name", null: false
    t.string "native_currency", default: "ETH"
    t.string "network_type", default: "mainnet", null: false
    t.integer "poll_interval_seconds", default: 2
    t.string "rpc_url", null: false
    t.string "rpc_url_fallback"
    t.boolean "supports_block_receipts", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["chain_id"], name: "index_chain_configs_on_chain_id", unique: true
  end

  create_table "indexed_blocks", force: :cascade do |t|
    t.bigint "base_fee_per_gas"
    t.string "block_hash", limit: 66, null: false
    t.integer "chain_id", default: 1, null: false
    t.datetime "created_at", null: false
    t.jsonb "extra_data", default: {}
    t.bigint "gas_limit"
    t.bigint "gas_used"
    t.string "miner", limit: 42
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
    t.string "contract_address", limit: 42
    t.datetime "created_at", null: false
    t.jsonb "extra_data", default: {}
    t.string "from_address", limit: 42, null: false
    t.bigint "gas_price"
    t.bigint "gas_used"
    t.text "input_data"
    t.bigint "max_fee_per_gas"
    t.bigint "max_priority_fee_per_gas"
    t.integer "status"
    t.string "to_address", limit: 42
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
end
