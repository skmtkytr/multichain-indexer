# frozen_string_literal: true

require 'test_helper'

class IndexerCursorTest < ActiveSupport::TestCase
  setup do
    @cursor = IndexerCursor.find_or_create_by!(chain_id: 88888) do |c|
      c.status = 'stopped'
      c.last_indexed_block = 0
    end
  end

  teardown do
    IndexerCursor.where(chain_id: 88888).delete_all
  end

  # ── Validations ──

  test 'requires chain_id' do
    c = IndexerCursor.new(status: 'stopped')
    assert_not c.valid?
    assert_includes c.errors[:chain_id], "can't be blank"
  end

  test 'chain_id must be unique' do
    dup = IndexerCursor.new(chain_id: 88888, status: 'stopped')
    assert_not dup.valid?
    assert_includes dup.errors[:chain_id], 'has already been taken'
  end

  test 'status must be valid' do
    c = IndexerCursor.new(chain_id: 77777, status: 'bogus')
    assert_not c.valid?
    assert_includes c.errors[:status], 'is not included in the list'
  end

  test 'valid statuses' do
    %w[running stopped error].each do |s|
      c = IndexerCursor.new(chain_id: 77770 + %w[running stopped error].index(s), status: s)
      assert c.valid?, "#{s} should be valid"
    end
  ensure
    IndexerCursor.where('chain_id >= 77770 AND chain_id <= 77772').delete_all
  end

  # ── running? ──

  test 'running? returns true when running' do
    @cursor.update!(status: 'running')
    assert @cursor.running?
  end

  test 'running? returns false when stopped' do
    assert_not @cursor.running?
  end

  # ── State transitions ──

  test 'mark_running! sets status and clears error' do
    @cursor.update!(status: 'error', error_message: 'boom')
    @cursor.mark_running!
    assert_equal 'running', @cursor.reload.status
    assert_nil @cursor.error_message
  end

  test 'mark_stopped! sets status to stopped' do
    @cursor.update!(status: 'running')
    @cursor.mark_stopped!
    assert_equal 'stopped', @cursor.reload.status
  end

  test 'mark_error! sets status and message' do
    @cursor.mark_error!('something broke')
    assert_equal 'error', @cursor.reload.status
    assert_equal 'something broke', @cursor.error_message
  end

  # ── advance! ──

  test 'advance! updates last_indexed_block' do
    @cursor.advance!(42)
    assert_equal 42, @cursor.reload.last_indexed_block
  end

  # ── Scopes ──

  test 'active scope returns only running cursors' do
    @cursor.update!(status: 'running')
    stopped = IndexerCursor.find_or_create_by!(chain_id: 88889) { |c| c.status = 'stopped'; c.last_indexed_block = 0 }

    active = IndexerCursor.active
    assert_includes active, @cursor
    assert_not_includes active, stopped
  ensure
    IndexerCursor.where(chain_id: 88889).delete_all
  end
end
