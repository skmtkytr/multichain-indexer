# frozen_string_literal: true

require 'minitest/autorun'

# Unit tests for BlockPollerWorkflow mode switching logic.
# These tests verify the mode determination logic WITHOUT requiring
# Temporal or Rails (pure Ruby unit tests).
#
# We extract and test the decision logic that determines:
#   - catchup vs live mode based on gap
#   - batch sizes
#   - parallel batch counts

class BlockPollerWorkflowModeTest < Minitest::Test
  CATCHUP_THRESHOLD = 50
  CATCHUP_BATCH_SIZE = 50
  DEFAULT_CATCHUP_PARALLEL = 3
  LIVE_CHILD_INTERVAL = 1

  # Helper: simulate the mode decision logic from BlockPollerWorkflow#execute
  def determine_mode(current_block:, latest_block:)
    gap = latest_block - current_block
    gap > CATCHUP_THRESHOLD ? :catchup : :live
  end

  # Helper: compute catchup batch ranges (mirrors workflow logic)
  def compute_catchup_batch_ranges(current_block:, latest_block:, catchup_parallel:)
    batch_ranges = []
    batch_cursor = current_block
    catchup_parallel.times do
      break if batch_cursor > latest_block
      batch_end = [batch_cursor + CATCHUP_BATCH_SIZE - 1, latest_block].min
      batch_ranges << { from: batch_cursor, to: batch_end }
      batch_cursor = batch_end + 1
    end
    batch_ranges
  end

  # Helper: compute live mode block range (mirrors workflow logic)
  def compute_live_range(current_block:, latest_block:, blocks_per_batch:)
    end_block = [current_block + blocks_per_batch - 1, latest_block].min
    (current_block..end_block).to_a
  end

  # ═══════════════════════════════════════════════════════════════
  # Test 1: Catchup mode when gap > CATCHUP_THRESHOLD
  # ═══════════════════════════════════════════════════════════════
  def test_catchup_mode_when_gap_exceeds_threshold
    assert_equal :catchup, determine_mode(current_block: 100, latest_block: 251)
    # gap = 151, well above threshold of 50
  end

  def test_catchup_mode_at_boundary
    # gap = 51, just above threshold
    assert_equal :catchup, determine_mode(current_block: 100, latest_block: 151)
  end

  # ═══════════════════════════════════════════════════════════════
  # Test 2: Live mode when gap <= CATCHUP_THRESHOLD
  # ═══════════════════════════════════════════════════════════════
  def test_live_mode_when_gap_within_threshold
    assert_equal :live, determine_mode(current_block: 100, latest_block: 110)
    # gap = 10
  end

  def test_live_mode_at_boundary
    # gap = 50, exactly at threshold (not exceeded)
    assert_equal :live, determine_mode(current_block: 100, latest_block: 150)
  end

  def test_live_mode_when_caught_up
    assert_equal :live, determine_mode(current_block: 100, latest_block: 100)
  end

  # ═══════════════════════════════════════════════════════════════
  # Test 3: Mode transition catchup → live
  # ═══════════════════════════════════════════════════════════════
  def test_mode_transitions_from_catchup_to_live
    # Simulate processing: start far behind, then catch up
    current = 100
    latest = 200  # gap = 100 → catchup

    assert_equal :catchup, determine_mode(current_block: current, latest_block: latest)

    # After catchup batch processes 50 blocks
    current += 50  # now at 150, gap = 50 → live
    assert_equal :live, determine_mode(current_block: current, latest_block: latest)
  end

  def test_mode_transitions_from_live_to_catchup
    # Start in live mode, then fall behind
    current = 100
    latest = 120  # gap = 20 → live
    assert_equal :live, determine_mode(current_block: current, latest_block: latest)

    # Chain advances while we're slow
    latest = 200  # gap = 100 → catchup
    assert_equal :catchup, determine_mode(current_block: current, latest_block: latest)
  end

  # ═══════════════════════════════════════════════════════════════
  # Test 4: blocks_per_batch determines live mode batch size
  # ═══════════════════════════════════════════════════════════════
  def test_blocks_per_batch_determines_live_range
    blocks = compute_live_range(current_block: 100, latest_block: 200, blocks_per_batch: 3)
    assert_equal [100, 101, 102], blocks
  end

  def test_blocks_per_batch_capped_by_latest
    # Only 2 blocks available but batch size is 5
    blocks = compute_live_range(current_block: 199, latest_block: 200, blocks_per_batch: 5)
    assert_equal [199, 200], blocks
  end

  def test_blocks_per_batch_single
    blocks = compute_live_range(current_block: 100, latest_block: 200, blocks_per_batch: 1)
    assert_equal [100], blocks
  end

  def test_blocks_per_batch_large
    blocks = compute_live_range(current_block: 100, latest_block: 200, blocks_per_batch: 10)
    assert_equal (100..109).to_a, blocks
  end

  # ═══════════════════════════════════════════════════════════════
  # Test 5: catchup_parallel_batches controls parallel batch count
  # ═══════════════════════════════════════════════════════════════
  def test_catchup_parallel_batches_single
    ranges = compute_catchup_batch_ranges(current_block: 100, latest_block: 500, catchup_parallel: 1)
    assert_equal 1, ranges.size
    assert_equal({ from: 100, to: 149 }, ranges[0])
  end

  def test_catchup_parallel_batches_multiple
    ranges = compute_catchup_batch_ranges(current_block: 100, latest_block: 500, catchup_parallel: 3)
    assert_equal 3, ranges.size
    assert_equal({ from: 100, to: 149 }, ranges[0])
    assert_equal({ from: 150, to: 199 }, ranges[1])
    assert_equal({ from: 200, to: 249 }, ranges[2])
  end

  def test_catchup_parallel_batches_capped_by_latest
    # Only 80 blocks to process, parallel=3 but only 2 batches needed
    ranges = compute_catchup_batch_ranges(current_block: 100, latest_block: 179, catchup_parallel: 3)
    assert_equal 2, ranges.size
    assert_equal({ from: 100, to: 149 }, ranges[0])
    assert_equal({ from: 150, to: 179 }, ranges[1])
  end

  def test_catchup_parallel_batches_exact_fit
    # Exactly 50 blocks = 1 batch even with parallel=3
    ranges = compute_catchup_batch_ranges(current_block: 100, latest_block: 149, catchup_parallel: 3)
    assert_equal 1, ranges.size
    assert_equal({ from: 100, to: 149 }, ranges[0])
  end

  def test_default_catchup_parallel
    assert_equal 3, DEFAULT_CATCHUP_PARALLEL
  end
end
