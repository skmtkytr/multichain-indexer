# frozen_string_literal: true

require 'test_helper'

class Api::V1::AssetTransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_chain_config(chain_id: 1)
    create_chain_config(chain_id: 10, name: 'Optimism', rpc_url: 'https://optimism.rpc')

    @t1 = create_asset_transfer(
      tx_hash: '0x' + 'a1' * 32, chain_id: 1, transfer_type: 'native',
      block_number: 100, log_index: -1, trace_index: -1
    )
    @t2 = create_asset_transfer(
      tx_hash: '0x' + 'a2' * 32, chain_id: 1, transfer_type: 'erc20',
      token_address: '0x' + 'ff' * 20, block_number: 101, log_index: 0, trace_index: -1
    )
    @t3 = create_asset_transfer(
      tx_hash: '0x' + 'a3' * 32, chain_id: 10, transfer_type: 'native',
      block_number: 200, log_index: -1, trace_index: -1
    )
  end

  test 'GET /api/v1/asset_transfers returns JSON' do
    get '/api/v1/asset_transfers'
    assert_response :success
    json = JSON.parse(response.body)
    assert_kind_of Array, json
    assert json.size >= 3
  end

  test 'filter by transfer_type' do
    get '/api/v1/asset_transfers', params: { type: 'erc20' }
    assert_response :success
    json = JSON.parse(response.body)
    assert json.all? { |t| t['transfer_type'] == 'erc20' }
    assert json.size >= 1
  end

  test 'filter by chain_id' do
    get '/api/v1/asset_transfers', params: { chain_id: 10 }
    assert_response :success
    json = JSON.parse(response.body)
    assert json.all? { |t| t['chain_id'] == 10 }
  end

  test 'limit parameter works' do
    get '/api/v1/asset_transfers', params: { limit: 1 }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json.size
  end
end
