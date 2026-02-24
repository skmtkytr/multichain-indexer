# frozen_string_literal: true

class RemoveWebhookProcessedFromAssetTransfers < ActiveRecord::Migration[8.0]
  def change
    remove_column :asset_transfers, :webhook_processed, :boolean, default: false, null: false
  end
end
