require "temporalio/client"

module TemporalClient
  class << self
    def connection
      @connection ||= Temporalio::Client.connect(
        ENV.fetch("TEMPORAL_HOST", "temporal:7233"),
        ENV.fetch("TEMPORAL_NAMESPACE", "default")
      )
    end

    def reset!
      @connection = nil
    end
  end
end
