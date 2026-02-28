# frozen_string_literal: true

require 'test_helper'

class Api::V1::BlocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_chain_config(chain_id: 1)
    @block1 = create_indexed_block(number: 100, chain_id: 1, block_hash: '0x' + 'a1' * 32, parent_hash: '0x' + 'b1' * 32)
    @block2 = create_indexed_block(number: 101, chain_id: 1, block_hash: '0x' + 'a2' * 32, parent_hash: '0x' + 'b2' * 32)
    @block3 = create_indexed_block(number: 200, chain_id: 2, block_hash: '0x' + 'a3' * 32, parent_hash: '0x' + 'b3' * 32)
  end

  test 'GET /api/v1/blocks returns JSON' do
    get '/api/v1/blocks', params: { chain_id: 1 }
    assert_response :success
    json = JSON.parse(response.body)
    assert_kind_of Array, json
    assert json.size >= 2
  end

  test 'pagination with limit and offset' do
    get '/api/v1/blocks', params: { chain_id: 1, limit: 1, offset: 0 }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json.size
  end

  test 'filter by chain_id' do
    get '/api/v1/blocks', params: { chain_id: 2 }
    assert_response :success
    json = JSON.parse(response.body)
    assert json.all? { |b| b['chain_id'] == 2 }
  end

  test 'GET /api/v1/blocks/:number returns single block' do
    get "/api/v1/blocks/#{@block1.number}", params: { chain_id: 1 }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal @block1.number, json['number']
  end

  test 'GET /api/v1/blocks/:number returns 404 for missing block' do
    get '/api/v1/blocks/999999', params: { chain_id: 1 }
    assert_response :not_found
  end
end
