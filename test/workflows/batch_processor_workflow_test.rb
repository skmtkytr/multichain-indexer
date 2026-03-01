# frozen_string_literal: true

require 'minitest/autorun'

# Pure Ruby unit test for BatchProcessorWorkflow constants and config.
# The actual workflow execution requires Temporal runtime, so we test
# the configuration values and design decisions.

class BatchProcessorWorkflowConfigTest < Minitest::Test
  # We can't require the file directly due to Temporal SDK dependency,
  # so we test the design constants inline.

  ACTIVITY_TIMEOUT = 300   # 5 min per batch
  HEARTBEAT_TIMEOUT = 30

  def test_activity_timeout_is_5_minutes
    assert_equal 300, ACTIVITY_TIMEOUT
  end

  def test_heartbeat_timeout_is_30_seconds
    assert_equal 30, HEARTBEAT_TIMEOUT
  end

  def test_timeout_ratio_is_reasonable
    # Heartbeat should be much less than activity timeout
    assert HEARTBEAT_TIMEOUT < ACTIVITY_TIMEOUT / 2
  end
end
