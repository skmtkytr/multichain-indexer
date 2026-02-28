# frozen_string_literal: true

require 'test_helper'

class TransferDecoderTest < ActiveSupport::TestCase
  setup do
    @chain_id = 1
    create_chain_config(chain_id: @chain_id)
  end

  # ── ERC-20 Transfer ──

  test 'decodes ERC-20 Transfer log' do
    amount = 1_000_000 * 10**18
    amount_hex = amount.to_s(16).rjust(64, '0')
    logs = [{
      'topics' => [
        Decoders::Erc20TransferDecoder::TOPIC0,
        '0x' + '0' * 24 + 'aabbccddee' * 4, # from
        '0x' + '0' * 24 + '1122334455' * 4   # to
      ],
      'data' => "0x#{amount_hex}",
      'address' => '0x' + 'ff' * 20,
      'logIndex' => '0x0',
      'transactionHash' => '0x' + 'ab' * 32
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, logs: logs)
    assert_equal 1, result[:count]
    t = result[:transfers].first
    assert_equal 'erc20', t[:transfer_type]
    assert_equal amount.to_s, t[:amount]
    assert_equal '0x' + 'ff' * 20, t[:token_address]
  end

  # ── ERC-721 Transfer ──

  test 'decodes ERC-721 Transfer log (4 topics)' do
    token_id = 42
    logs = [{
      'topics' => [
        Decoders::Erc20TransferDecoder::TOPIC0,
        '0x' + '0' * 24 + 'aa' * 20,
        '0x' + '0' * 24 + 'bb' * 20,
        '0x' + token_id.to_s(16).rjust(64, '0')
      ],
      'data' => '0x',
      'address' => '0x' + 'cc' * 20,
      'logIndex' => '0x1',
      'transactionHash' => '0x' + 'dd' * 32
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, logs: logs)
    assert_equal 1, result[:count]
    t = result[:transfers].first
    assert_equal 'erc721', t[:transfer_type]
    assert_equal '1', t[:amount]
    assert_equal '42', t[:token_id]
  end

  # ── ERC-1155 TransferSingle ──

  test 'decodes ERC-1155 TransferSingle' do
    token_id = 7
    value = 100
    data = '0x' + token_id.to_s(16).rjust(64, '0') + value.to_s(16).rjust(64, '0')
    logs = [{
      'topics' => [
        Decoders::Erc1155Decoder::TRANSFER_SINGLE,
        '0x' + '0' * 24 + 'aa' * 20, # operator
        '0x' + '0' * 24 + 'bb' * 20, # from
        '0x' + '0' * 24 + 'cc' * 20  # to
      ],
      'data' => data,
      'address' => '0x' + 'dd' * 20,
      'logIndex' => '0x2',
      'transactionHash' => '0x' + 'ee' * 32
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, logs: logs)
    assert_equal 1, result[:count]
    t = result[:transfers].first
    assert_equal 'erc1155', t[:transfer_type]
    assert_equal '100', t[:amount]
    assert_equal '7', t[:token_id]
  end

  # ── ERC-1155 TransferBatch ──

  test 'decodes ERC-1155 TransferBatch' do
    # ABI: offset_ids(32B) + offset_values(32B) + ids_count(32B) + id1 + id2 + values_count + val1 + val2
    ids_offset = 64 # 2 * 32 bytes
    vals_offset = 64 + 32 + 64 # after offset fields + ids_count + 2 ids = 160 bytes
    hex = ids_offset.to_s(16).rjust(64, '0') +
          vals_offset.to_s(16).rjust(64, '0') +
          (2).to_s(16).rjust(64, '0') + # ids count
          (10).to_s(16).rjust(64, '0') + # id=10
          (20).to_s(16).rjust(64, '0') + # id=20
          (2).to_s(16).rjust(64, '0') + # values count
          (5).to_s(16).rjust(64, '0') +  # value=5
          (15).to_s(16).rjust(64, '0')   # value=15

    logs = [{
      'topics' => [
        Decoders::Erc1155Decoder::TRANSFER_BATCH,
        '0x' + '0' * 24 + 'aa' * 20,
        '0x' + '0' * 24 + 'bb' * 20,
        '0x' + '0' * 24 + 'cc' * 20
      ],
      'data' => "0x#{hex}",
      'address' => '0x' + 'dd' * 20,
      'logIndex' => '0x3',
      'transactionHash' => '0x' + 'ff' * 32
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, logs: logs)
    assert_equal 2, result[:count]
    assert_equal '10', result[:transfers][0][:token_id]
    assert_equal '5', result[:transfers][0][:amount]
    assert_equal '20', result[:transfers][1][:token_id]
    assert_equal '15', result[:transfers][1][:amount]
  end

  # ── Native transfer ──

  test 'extracts native transfers from transactions' do
    txs = [{
      'hash' => '0x' + 'ab' * 32,
      'from' => '0x' + 'aa' * 20,
      'to' => '0x' + 'bb' * 20,
      'value' => '0xde0b6b3a7640000' # 1 ETH
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, transactions: txs)
    assert_equal 1, result[:count]
    t = result[:transfers].first
    assert_equal 'native', t[:transfer_type]
    assert_equal '1000000000000000000', t[:amount]
  end

  test 'skips zero-value native transactions' do
    txs = [{
      'hash' => '0x' + 'ab' * 32,
      'from' => '0x' + 'aa' * 20,
      'to' => '0x' + 'bb' * 20,
      'value' => '0x0'
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, transactions: txs)
    assert_equal 0, result[:count]
  end

  # ── Beacon withdrawals ──

  test 'decodes beacon withdrawals' do
    withdrawals = [{
      'index' => '0x1',
      'address' => '0x' + 'aa' * 20,
      'amount' => '0x3b9aca00' # 1 Gwei in hex
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, withdrawals: withdrawals)
    assert_equal 1, result[:count]
    t = result[:transfers].first
    assert_equal 'withdrawal', t[:transfer_type]
    assert_equal (0x3b9aca00 * 1_000_000_000).to_s, t[:amount]
  end

  # ── WETH deposit ──

  test 'decodes WETH Deposit event' do
    amount = 2 * 10**18
    logs = [{
      'topics' => [
        Decoders::WethDecoder::DEPOSIT_TOPIC,
        '0x' + '0' * 24 + 'aa' * 20
      ],
      'data' => "0x#{amount.to_s(16).rjust(64, '0')}",
      'address' => '0x' + 'cc' * 20,
      'logIndex' => '0x0',
      'transactionHash' => '0x' + 'dd' * 32
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, logs: logs)
    assert_equal 1, result[:count]
    t = result[:transfers].first
    assert_equal 'erc20', t[:transfer_type]
    assert_equal Decoders::BeaconWithdrawalDecoder::ZERO_ADDRESS, t[:from_address]
  end

  # ── WETH withdrawal ──

  test 'decodes WETH Withdrawal event' do
    amount = 3 * 10**18
    logs = [{
      'topics' => [
        Decoders::WethDecoder::WITHDRAWAL_TOPIC,
        '0x' + '0' * 24 + 'aa' * 20
      ],
      'data' => "0x#{amount.to_s(16).rjust(64, '0')}",
      'address' => '0x' + 'cc' * 20,
      'logIndex' => '0x0',
      'transactionHash' => '0x' + 'dd' * 32
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, logs: logs)
    assert_equal 1, result[:count]
    t = result[:transfers].first
    assert_equal 'erc20', t[:transfer_type]
    assert_equal '0x0000000000000000000000000000000000000000', t[:to_address]
  end

  # ── Unknown topic ──

  test 'skips unknown log topics gracefully' do
    logs = [{
      'topics' => ['0x' + 'ff' * 32],
      'data' => '0x',
      'address' => '0x' + 'aa' * 20,
      'logIndex' => '0x0',
      'transactionHash' => '0x' + 'bb' * 32
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, logs: logs)
    assert_equal 0, result[:count]
  end

  test 'skips logs with no topics' do
    logs = [{
      'topics' => [],
      'data' => '0x',
      'address' => '0x' + 'aa' * 20,
      'logIndex' => '0x0',
      'transactionHash' => '0x' + 'bb' * 32
    }]

    result = TransferDecoder.decode(chain_id: @chain_id, block_number: 100, logs: logs)
    assert_equal 0, result[:count]
  end
end
