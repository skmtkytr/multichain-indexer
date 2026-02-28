# frozen_string_literal: true

require 'test_helper'

class Api::V1::SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sub = create_subscription(
      address: '0x' + 'aa' * 20,
      webhook_url: 'https://example.com/hook',
      label: 'test-sub'
    )
  end

  test 'GET /api/v1/subscriptions returns list' do
    get '/api/v1/subscriptions'
    assert_response :success
    json = JSON.parse(response.body)
    assert_kind_of Array, json
    assert json.size >= 1
  end

  test 'GET /api/v1/subscriptions/:id returns detail with secret' do
    get "/api/v1/subscriptions/#{@sub.id}"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal @sub.id, json['id']
    assert json.key?('secret')
    assert_not_nil json['secret']
  end

  test 'POST /api/v1/subscriptions creates subscription' do
    post '/api/v1/subscriptions', params: {
      address: '0x' + 'bb' * 20,
      webhook_url: 'https://example.com/new',
      direction: 'incoming'
    }
    assert_response :created
    json = JSON.parse(response.body)
    assert_equal '0x' + 'bb' * 20, json['address']
    assert_equal 'incoming', json['direction']
  end

  test 'POST /api/v1/subscriptions generates HMAC secret' do
    post '/api/v1/subscriptions', params: {
      address: '0x' + 'cc' * 20,
      webhook_url: 'https://example.com/secret'
    }
    assert_response :created
    sub = AddressSubscription.last
    assert_not_nil sub.secret
    assert_equal 64, sub.secret.length # hex(32 bytes)
  end

  test 'PATCH /api/v1/subscriptions/:id updates subscription' do
    patch "/api/v1/subscriptions/#{@sub.id}", params: { label: 'updated' }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'updated', json['label']
  end

  test 'DELETE /api/v1/subscriptions/:id deletes subscription' do
    assert_difference('AddressSubscription.count', -1) do
      delete "/api/v1/subscriptions/#{@sub.id}"
    end
    assert_response :success
  end

  test 'POST with invalid params returns errors' do
    post '/api/v1/subscriptions', params: { address: '' }
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json.key?('errors')
  end
end
