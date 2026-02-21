# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.cache_store = :memory_store
  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.log_level = :debug

  # Log to STDOUT so docker logs can capture it
  config.logger = ActiveSupport::Logger.new($stdout)
  config.logger.formatter = config.log_formatter
end
