require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module EvmIndexer
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
    config.eager_load_paths += %W[
      #{config.root}/app/workflows
      #{config.root}/app/activities
      #{config.root}/app/services
    ]
    config.time_zone = "UTC"
  end
end
