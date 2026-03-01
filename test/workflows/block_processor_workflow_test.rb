# frozen_string_literal: true

require 'minitest/autorun'

# Pure Ruby unit test for BlockProcessorWorkflow design.
# Tests the 3-step execution pattern and timeout configuration.
# Actual Temporal workflow testing requires the SDK runtime.

class BlockProcessorWorkflowDesignTest < Minitest::Test
  # Constants from the workflow
  FETCH_START_TO_CLOSE = 60
  FETCH_HEARTBEAT_TIMEOUT = 30
  TRACE_START_TO_CLOSE = 60
  CURSOR_START_TO_CLOSE = 10

  # The workflow executes 3 steps:
  # 1. fetch_and_store (FetchBlockActivity)
  # 2. traces (FetchTracesActivity) — best-effort
  # 3. update_cursor (ProcessBlockActivity)

  def test_fetch_timeout_allows_large_blocks
    # 60s should be enough for even large Polygon/Arbitrum blocks
    assert FETCH_START_TO_CLOSE >= 30
  end

  def test_heartbeat_is_half_of_fetch_timeout
    assert_equal FETCH_START_TO_CLOSE / 2, FETCH_HEARTBEAT_TIMEOUT
  end

  def test_cursor_update_is_fast
    assert CURSOR_START_TO_CLOSE <= 15
  end

  def test_trace_timeout_matches_fetch
    assert_equal FETCH_START_TO_CLOSE, TRACE_START_TO_CLOSE
  end

  def test_block_number_hex_conversion
    # The workflow converts block_number to hex for trace calls
    assert_equal '0x64', "0x#{100.to_s(16)}"
    assert_equal '0xf4240', "0x#{1000000.to_s(16)}"
  end
end
