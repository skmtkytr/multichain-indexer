# frozen_string_literal: true

class CreateEventSignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :event_signatures do |t|
      t.string :signature_hash, null: false
      t.string :event_name, null: false
      t.string :full_signature, null: false
      t.jsonb :abi_json

      t.timestamps
    end
    add_index :event_signatures, :signature_hash, unique: true
  end
end
