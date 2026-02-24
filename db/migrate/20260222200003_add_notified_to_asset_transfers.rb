# frozen_string_literal: true

class AddNotifiedToAssetTransfers < ActiveRecord::Migration[8.0]
  def change
    add_column :asset_transfers, :webhook_processed, :boolean, default: false, null: false
    add_index :asset_transfers, :webhook_processed, where: 'webhook_processed = false'
  end
end
