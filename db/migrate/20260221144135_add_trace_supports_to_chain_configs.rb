# frozen_string_literal: true

class AddTraceSupportsToChainConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :chain_configs, :trace_method, :string
    add_column :chain_configs, :supports_trace, :boolean, default: false
  end
end
