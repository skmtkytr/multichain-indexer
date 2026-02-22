# frozen_string_literal: true

class AddSidecarUrlToChainConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :chain_configs, :sidecar_url, :string
  end
end
