# frozen_string_literal: true

class AddPrivacyToAssetTransfers < ActiveRecord::Migration[8.0]
  def change
    add_column :asset_transfers, :confidential, :boolean, default: false
    add_column :asset_transfers, :privacy_protocol, :string  # mweb, shielded, coinjoin, null
  end
end
