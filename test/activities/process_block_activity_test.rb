# frozen_string_literal: true

require 'test_helper'

class ProcessBlockActivityTest < ActiveSupport::TestCase
  setup do
    @activity = Indexer::ProcessBlockActivity.new
  end

  # ── update_cursor ──

  test 'update_cursor creates and advances cursor' do
    # Clean up first
    IndexerCursor.where(chain_id: 88801).delete_all

    @activity.execute('action' => 'update_cursor', 'chain_id' => 88801, 'block_number' => 200)

    cursor = IndexerCursor.find_by(chain_id: 88801)
    assert_not_nil cursor
    assert_equal 200, cursor.last_indexed_block
  ensure
    IndexerCursor.where(chain_id: 88801).delete_all
  end

  # ── hex conversion accuracy ──

  test 'hex to integer conversions are accurate' do
    assert_equal 100, '0x64'.to_i(16)
    assert_equal 21000, '0x5208'.to_i(16)
    assert_equal 1000000, '0xf4240'.to_i(16)
    assert_equal 1_000_000_000, '0x3b9aca00'.to_i(16)
    assert_equal 1_000_000_000_000_000_000, '0xde0b6b3a7640000'.to_i(16)
  end

  # ── process_full ──

  test 'process_full stores block and transactions' do
    # Clean test data
    chain_id = 88802
    IndexedBlock.where(chain_id: chain_id, number: 100).delete_all
    IndexedTransaction.where(chain_id: chain_id).delete_all

    params = {
      'action' => 'process_full',
      'block_data' => {
        'chain_id' => chain_id,
        'number' => '0x64',
        'hash' => '0xblockhash',
        'parentHash' => '0xparent',
        'timestamp' => '0x60',
        'miner' => '0xMINER',
        'gasUsed' => '0x5208',
        'gasLimit' => '0xf4240',
        'baseFeePerGas' => '0x3b9aca00',
        'transactions' => [
          {
            'hash' => '0xtestprocesstx1',
            'transactionIndex' => '0x0',
            'from' => '0xSENDER',
            'to' => '0xRECEIVER',
            'value' => '0xde0b6b3a7640000',
            'gasPrice' => '0x3b9aca00',
            'input' => '0x'
          }
        ]
      },
      'receipts' => [
        { 'transactionHash' => '0xtestprocesstx1', 'gasUsed' => '0x5208', 'status' => '0x1' }
      ],
      'logs' => []
    }

    @activity.execute(params)

    block = IndexedBlock.find_by(chain_id: chain_id, number: 100)
    assert_not_nil block
    assert_equal '0xblockhash', block.block_hash

    tx = IndexedTransaction.find_by(chain_id: chain_id, tx_hash: '0xtestprocesstx1')
    assert_not_nil tx
    assert_equal 1_000_000_000_000_000_000, tx.value.to_i
  ensure
    IndexedBlock.where(chain_id: chain_id, number: 100).delete_all
    IndexedTransaction.where(chain_id: chain_id, tx_hash: '0xtestprocesstx1').delete_all
  end
end
