# frozen_string_literal: true

class CreateUtxoTables < ActiveRecord::Migration[8.0]
  def change
    create_table :utxo_transactions do |t|
      t.integer  :chain_id,    null: false
      t.string   :txid,        null: false, limit: 64
      t.bigint   :block_number, null: false
      t.string   :block_hash,  limit: 64
      t.integer  :size
      t.integer  :vsize                    # virtual size (segwit)
      t.decimal  :fee,         precision: 30, scale: 0  # in satoshi
      t.boolean  :is_coinbase, default: false
      t.bigint   :lock_time
      t.integer  :input_count,  default: 0
      t.integer  :output_count, default: 0
      t.timestamps
    end

    add_index :utxo_transactions, %i[chain_id txid], unique: true
    add_index :utxo_transactions, %i[chain_id block_number]

    create_table :utxo_inputs do |t|
      t.integer  :chain_id,    null: false
      t.string   :txid,        null: false, limit: 64  # tx containing this input
      t.integer  :vin_index,   null: false
      t.string   :prev_txid,   limit: 64               # referenced tx (null for coinbase)
      t.integer  :prev_vout                             # referenced output index
      t.text     :script_sig
      t.jsonb    :witness,     default: []
      t.bigint   :sequence
      t.string   :address                               # resolved from prev output
      t.decimal  :amount,      precision: 30, scale: 0  # resolved from prev output (satoshi)
      t.boolean  :is_coinbase, default: false
      t.timestamps
    end

    add_index :utxo_inputs, %i[chain_id txid vin_index], unique: true
    add_index :utxo_inputs, :address
    add_index :utxo_inputs, %i[chain_id prev_txid prev_vout], name: 'idx_utxo_inputs_prev_output'

    create_table :utxo_outputs do |t|
      t.integer  :chain_id,       null: false
      t.string   :txid,           null: false, limit: 64
      t.integer  :vout_index,     null: false
      t.decimal  :amount,         precision: 30, scale: 0, null: false  # satoshi
      t.text     :script_pub_key
      t.string   :script_type                  # p2pkh, p2sh, p2wpkh, p2wsh, p2tr, nulldata, multisig, mweb_pegin
      t.string   :address                      # null for OP_RETURN, MWEB confidential
      t.boolean  :spent,          default: false
      t.string   :spent_by_txid,  limit: 64
      t.integer  :spent_by_vin
      t.boolean  :is_confidential, default: false  # MWEB / shielded
      t.timestamps
    end

    add_index :utxo_outputs, %i[chain_id txid vout_index], unique: true
    add_index :utxo_outputs, :address
    add_index :utxo_outputs, %i[chain_id spent], name: 'idx_utxo_outputs_unspent', where: 'spent = false'
  end
end
