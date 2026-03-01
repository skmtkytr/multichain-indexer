# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class IndexerControllerTest < ActionDispatch::IntegrationTest
      setup do
        RpcRateLimiter.reset!
      end

      test "GET status returns chain stats with rpc_stats" do
        # Create test chain config and cursor
        chain = ChainConfig.find_or_create_by!(chain_id: 99999) do |c|
          c.name = "Test Chain"
          c.rpc_url = "https://test-rpc.example.com"
          c.network_type = "testnet"
          c.chain_type = "evm"
          c.enabled = false # don't try to actually connect
        end

        IndexerCursor.find_or_create_by!(chain_id: 99999) do |c|
          c.last_indexed_block = 100
          c.status = "running"
        end

        get api_v1_indexer_status_path, params: { chain_id: 99999 }
        assert_response :success

        json = JSON.parse(response.body)
        assert_equal 99999, json["chain_id"]
        assert_equal "running", json["status"]
        assert_equal 100, json["current_block"]
        assert_includes json.keys, "gap"
        assert_includes json.keys, "rpc_stats"
        assert_includes json.keys, "blocks_count"
        assert_includes json.keys, "transactions_count"
        assert_includes json.keys, "logs_count"
      end

      test "GET status for non-existent chain returns not_initialized" do
        get api_v1_indexer_status_path, params: { chain_id: 11111 }
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 'not_initialized', json['status']
        assert_equal 0, json['current_block']
      end

      test "GET status with rpc_stats populated" do
        chain = ChainConfig.find_or_create_by!(chain_id: 99998) do |c|
          c.name = "Test Chain 2"
          c.rpc_url = "https://test-rpc2.example.com"
          c.network_type = "testnet"
          c.chain_type = "evm"
          c.enabled = false
        end

        # Simulate some RPC traffic
        RpcRateLimiter.acquire("https://test-rpc2.example.com", tokens: 3)

        get api_v1_indexer_status_path, params: { chain_id: 99998 }
        assert_response :success

        json = JSON.parse(response.body)
        rpc_stats = json["rpc_stats"]
        assert_not_nil rpc_stats
        assert_equal 3, rpc_stats["total_requests"]
      end
    end
  end
end
