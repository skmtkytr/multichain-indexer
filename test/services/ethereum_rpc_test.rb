# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'ostruct'

# Pure Ruby unit tests for EthereumRpc — no Rails, no DB, no network.
# We stub Net::HTTP and dependent classes inline.

# ActiveSupport-like extensions
class Array
  def presence; empty? ? nil : self; end unless method_defined?(:presence)
end
class String
  def presence; empty? ? nil : self; end unless method_defined?(:presence)
  def present?; !empty?; end unless method_defined?(:present?)
end
class NilClass
  def present?; false; end unless method_defined?(:present?)
  def presence; nil; end unless method_defined?(:presence)
end

# Minimal stubs for Rails dependencies
module Rails
  def self.logger
    @logger ||= begin
      l = Object.new
      def l.warn(*); end
      def l.info(*); end
      def l.debug(*); end
      def l.error(*); end
      l
    end
  end
end

# Stub RpcRateLimiter (only if not already loaded by Rails)
unless defined?(RpcRateLimiter) && RpcRateLimiter.respond_to?(:bucket_for)
  class RpcRateLimiter
    DEFAULT_RPS = 20
    def self.acquire(url, tokens: 1, rate: nil); 0.0; end
    def self.reset!; end
  end
end

# Stub ChainConfig (only if not already loaded by Rails)
unless defined?(ChainConfig) && ChainConfig.respond_to?(:cached_find)
  class ChainConfig
    def self.find_by(chain_id:)
      nil
    end

    def self.where(chain_id:)
      stub = Object.new
      def stub.update_all(*); end
      stub
    end
  end
end

# Now load the class under test
require_relative '../../app/services/ethereum_rpc'

class EthereumRpcTest < Minitest::Test
  # ── Helper to build a fake HTTP response ──
  def fake_response(body, code = '200')
    resp = Object.new
    resp.define_singleton_method(:body) { body }
    resp.define_singleton_method(:code) { code }
    resp
  end

  def stub_http_post(rpc, responses)
    call_idx = 0
    rpc.define_singleton_method(:http_post) do |_url, _body|
      resp = responses.is_a?(Array) ? responses[call_idx] : responses
      call_idx += 1
      resp
    end
  end

  # ══════════════════════════════════════════════════════════════
  # initialize
  # ══════════════════════════════════════════════════════════════

  def test_initialize_with_rpc_url
    rpc = EthereumRpc.new(rpc_url: 'https://my-rpc.com')
    assert_equal ['https://my-rpc.com'], rpc.instance_variable_get(:@rpc_urls)
  end

  def test_initialize_with_chain_id_and_config
    config = Object.new
    config.define_singleton_method(:rpc_url_list) { ['https://chain-rpc.com'] }
    config.define_singleton_method(:rpc_endpoints) { [] }

    original = ChainConfig.method(:find_by)
    ChainConfig.define_singleton_method(:find_by) { |**| config }
    rpc = EthereumRpc.new(chain_id: 1)
    assert_equal ['https://chain-rpc.com'], rpc.instance_variable_get(:@rpc_urls)
  ensure
    ChainConfig.define_singleton_method(:find_by, original)
  end

  def test_initialize_with_chain_id_no_config_falls_back_to_env
    ENV['ETHEREUM_RPC_URL'] = 'https://env-rpc.com'
    original = ChainConfig.method(:find_by)
    ChainConfig.define_singleton_method(:find_by) { |**| nil }
    rpc = EthereumRpc.new(chain_id: 999)
    assert_equal ['https://env-rpc.com'], rpc.instance_variable_get(:@rpc_urls)
  ensure
    ChainConfig.define_singleton_method(:find_by, original)
    ENV.delete('ETHEREUM_RPC_URL')
  end

  def test_initialize_no_args_uses_env
    ENV['ETHEREUM_RPC_URL'] = 'https://default-rpc.com'
    rpc = EthereumRpc.new
    assert_equal ['https://default-rpc.com'], rpc.instance_variable_get(:@rpc_urls)
  ensure
    ENV.delete('ETHEREUM_RPC_URL')
  end

  def test_initialize_extracts_rate_limits_from_endpoints
    config = Object.new
    config.define_singleton_method(:rpc_url_list) { ['https://a.com'] }
    config.define_singleton_method(:rpc_endpoints) {
      [{ 'url' => 'https://a.com', 'rate_limit' => '50' }]
    }

    original = ChainConfig.method(:find_by)
    ChainConfig.define_singleton_method(:find_by) { |**| config }
    rpc = EthereumRpc.new(chain_id: 1)
    limits = rpc.instance_variable_get(:@rpc_rate_limits)
    assert_equal 50, limits['https://a.com']
  ensure
    ChainConfig.define_singleton_method(:find_by, original)
  end

  # ══════════════════════════════════════════════════════════════
  # get_block_number
  # ══════════════════════════════════════════════════════════════

  def test_get_block_number_converts_hex_to_integer
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.define_singleton_method(:call_with_fallback) do |method, params = []|
      '0x1234'
    end

    assert_equal 0x1234, rpc.get_block_number
  end

  def test_get_block_number_with_finalized_tag
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.define_singleton_method(:call_with_fallback) do |method, params = []|
      { 'number' => '0xff' }
    end

    assert_equal 255, rpc.get_block_number(tag: 'finalized')
  end

  def test_get_block_number_finalized_returns_nil_when_unsupported
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.define_singleton_method(:call_with_fallback) do |method, params = []|
      nil
    end

    assert_nil rpc.get_block_number(tag: 'finalized')
  end

  # ══════════════════════════════════════════════════════════════
  # get_block_by_number
  # ══════════════════════════════════════════════════════════════

  def test_get_block_by_number_converts_integer_to_hex
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    captured_params = nil
    rpc.define_singleton_method(:call_with_fallback) do |method, params = []|
      captured_params = params
      { 'number' => '0x10' }
    end

    rpc.get_block_by_number(16)
    assert_equal '0x10', captured_params[0]
    assert_equal true, captured_params[1]
  end

  def test_get_block_by_number_passes_string_through
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    captured_params = nil
    rpc.define_singleton_method(:call_with_fallback) do |method, params = []|
      captured_params = params
      {}
    end

    rpc.get_block_by_number('0xabc')
    assert_equal '0xabc', captured_params[0]
  end

  # ══════════════════════════════════════════════════════════════
  # batch_call — rate limit retry
  # ══════════════════════════════════════════════════════════════

  def test_batch_call_retries_on_rate_limit
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    call_count = 0

    stub_http_post(rpc, lambda {
      call_count += 1
      if call_count == 1
        [{ 'id' => 1, 'error' => { 'code' => -32005, 'message' => 'exceeded the RPS limit' } }].to_json
      else
        [{ 'id' => 2, 'result' => '0x1' }].to_json
      end
    })
    # Override sleep to not actually wait
    rpc.define_singleton_method(:sleep) { |_| }

    results = rpc.batch_call([{ method: 'eth_blockNumber', params: [] }])
    assert_equal ['0x1'], results
    assert_equal 2, call_count
  end

  def test_batch_call_raises_after_max_retries
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')

    stub_http_post(rpc, [{ 'id' => 1, 'error' => { 'code' => -32005, 'message' => 'rate limit' } }].to_json)
    rpc.define_singleton_method(:sleep) { |_| }

    assert_raises(EthereumRpc::RpcError) do
      rpc.batch_call([{ method: 'eth_blockNumber', params: [] }])
    end
  end

  def test_batch_call_sorts_results_by_id
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    stub_http_post(rpc, [
      { 'id' => 2, 'result' => 'second' },
      { 'id' => 1, 'result' => 'first' }
    ].to_json)

    results = rpc.batch_call([
      { method: 'a', params: [] },
      { method: 'b', params: [] }
    ])
    assert_equal 'first', results[0]
    assert_equal 'second', results[1]
  end

  # ══════════════════════════════════════════════════════════════
  # batch_get_transaction_receipts — chunk splitting
  # ══════════════════════════════════════════════════════════════

  def test_batch_get_transaction_receipts_empty
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    assert_equal [], rpc.batch_get_transaction_receipts([])
  end

  def test_batch_get_transaction_receipts_chunks
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.instance_variable_set(:@batch_limit, 3)

    batch_calls = []
    rpc.define_singleton_method(:batch_call) do |requests|
      batch_calls << requests.size
      requests.map { |_| 'receipt' }
    end

    hashes = (1..7).map { |i| "0x#{i}" }
    results = rpc.batch_get_transaction_receipts(hashes)

    assert_equal 7, results.size
    assert_equal [3, 3, 1], batch_calls
  end

  # ══════════════════════════════════════════════════════════════
  # fetch_full_block
  # ══════════════════════════════════════════════════════════════

  def test_fetch_full_block_combines_block_receipts_logs
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.instance_variable_set(:@chain_id, 1)

    rpc.define_singleton_method(:get_block_by_number) do |num, full_transactions:|
      { 'transactions' => [{ 'hash' => '0xabc' }], 'chain_id' => 1 }
    end
    rpc.define_singleton_method(:get_block_receipts) do |num|
      [{ 'transactionHash' => '0xabc', 'logs' => [{ 'logIndex' => '0x0' }] }]
    end

    result = rpc.fetch_full_block(100)
    assert_equal 1, result['block']['chain_id']
    assert_equal 1, result['receipts'].size
    assert_equal 1, result['logs'].size
  end

  def test_fetch_full_block_returns_nil_when_block_missing
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.define_singleton_method(:get_block_by_number) { |*| nil }

    assert_nil rpc.fetch_full_block(999)
  end

  def test_fetch_full_block_falls_back_to_batch_receipts
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.instance_variable_set(:@chain_id, 1)

    rpc.define_singleton_method(:get_block_by_number) do |num, full_transactions:|
      { 'transactions' => [{ 'hash' => '0xabc' }] }
    end
    rpc.define_singleton_method(:get_block_receipts) do |_|
      raise EthereumRpc::RpcError, 'method not supported'
    end
    rpc.define_singleton_method(:batch_get_transaction_receipts) do |hashes|
      [{ 'transactionHash' => '0xabc', 'logs' => [] }]
    end

    result = rpc.fetch_full_block(100, supports_block_receipts: true)
    assert_equal 1, result['receipts'].size
  end

  def test_fetch_full_block_uses_batch_when_not_supported
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')

    rpc.define_singleton_method(:get_block_by_number) do |num, full_transactions:|
      { 'transactions' => [] }
    end
    rpc.define_singleton_method(:batch_get_transaction_receipts) do |hashes|
      []
    end

    result = rpc.fetch_full_block(100, supports_block_receipts: false)
    assert_equal [], result['receipts']
  end

  # ══════════════════════════════════════════════════════════════
  # call_with_fallback
  # ══════════════════════════════════════════════════════════════

  def test_call_with_fallback_tries_next_endpoint_on_rate_limit
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.instance_variable_set(:@rpc_urls, ['https://a.com', 'https://b.com'])
    rpc.define_singleton_method(:sleep) { |_| }

    calls = []
    rpc.define_singleton_method(:call_single) do |url, method, params|
      calls << url
      if url == 'https://a.com'
        raise EthereumRpc::RpcError, 'exceeded the RPS limit'
      end
      'ok'
    end

    result = rpc.send(:call_with_fallback, 'eth_blockNumber')
    assert_equal 'ok', result
    assert_equal ['https://a.com', 'https://b.com'], calls
  end

  def test_call_with_fallback_raises_all_endpoints_failed
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.instance_variable_set(:@rpc_urls, ['https://a.com'])

    rpc.define_singleton_method(:call_single) do |url, method, params|
      raise StandardError, 'connection refused'
    end

    assert_raises(EthereumRpc::AllEndpointsFailedError) do
      rpc.send(:call_with_fallback, 'eth_blockNumber')
    end
  end

  def test_call_with_fallback_propagates_non_rate_limit_rpc_error
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.instance_variable_set(:@rpc_urls, ['https://a.com', 'https://b.com'])

    rpc.define_singleton_method(:call_single) do |url, method, params|
      raise EthereumRpc::RpcError, 'some other error'
    end

    assert_raises(EthereumRpc::RpcError) do
      rpc.send(:call_with_fallback, 'eth_blockNumber')
    end
  end

  # ══════════════════════════════════════════════════════════════
  # call_single — rate limit detection & retry
  # ══════════════════════════════════════════════════════════════

  def test_call_single_retries_on_rate_limit_code
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.define_singleton_method(:sleep) { |_| }

    call_count = 0
    stub_http_post(rpc, lambda {
      call_count += 1
      if call_count == 1
        { 'jsonrpc' => '2.0', 'id' => 1, 'error' => { 'code' => -32005, 'message' => 'rate limit' } }.to_json
      else
        { 'jsonrpc' => '2.0', 'id' => 2, 'result' => '0x1' }.to_json
      end
    })

    result = rpc.send(:call_single, 'https://rpc.test', 'eth_blockNumber', [])
    assert_equal '0x1', result
    assert_equal 2, call_count
  end

  def test_call_single_raises_non_retryable_error
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')

    stub_http_post(rpc,
      { 'jsonrpc' => '2.0', 'id' => 1, 'error' => { 'code' => -32601, 'message' => 'method not found' } }.to_json
    )

    assert_raises(EthereumRpc::NonRetryableError) do
      rpc.send(:call_single, 'https://rpc.test', 'eth_foo', [])
    end
  end

  def test_call_single_raises_non_retryable_on_pattern_match
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')

    stub_http_post(rpc,
      { 'jsonrpc' => '2.0', 'id' => 1, 'error' => { 'code' => -32000, 'message' => 'invalid block number' } }.to_json
    )

    assert_raises(EthereumRpc::NonRetryableError) do
      rpc.send(:call_single, 'https://rpc.test', 'eth_getBlockByNumber', [])
    end
  end

  def test_call_single_uses_try_again_in_delay
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    sleep_values = []
    rpc.define_singleton_method(:sleep) { |v| sleep_values << v }

    call_count = 0
    stub_http_post(rpc, lambda {
      call_count += 1
      if call_count == 1
        { 'jsonrpc' => '2.0', 'id' => 1, 'error' => {
          'code' => -32005, 'message' => 'rate limit',
          'data' => { 'try_again_in' => 500 }
        }}.to_json
      else
        { 'jsonrpc' => '2.0', 'id' => 2, 'result' => 'ok' }.to_json
      end
    })

    rpc.send(:call_single, 'https://rpc.test', 'eth_blockNumber', [])
    assert_in_delta 0.5, sleep_values.first, 0.01
  end

  # ══════════════════════════════════════════════════════════════
  # acquire_rate_limit
  # ══════════════════════════════════════════════════════════════

  def test_acquire_rate_limit_calls_rpc_rate_limiter
    rpc = EthereumRpc.new(rpc_url: 'https://rpc.test')
    rpc.instance_variable_set(:@rpc_rate_limits, { 'https://rpc.test' => 50 })

    acquired = false
    original = RpcRateLimiter.method(:acquire)
    RpcRateLimiter.define_singleton_method(:acquire) { |url, tokens: 1, rate: nil| acquired = true; 0.0 }
    rpc.send(:acquire_rate_limit, 'https://rpc.test')
    assert acquired
  ensure
    RpcRateLimiter.define_singleton_method(:acquire, original)
  end

  # ══════════════════════════════════════════════════════════════
  # http_post stub helper — lambda support
  # ══════════════════════════════════════════════════════════════

  private

  def stub_http_post(rpc, response_or_lambda)
    if response_or_lambda.respond_to?(:call)
      rpc.define_singleton_method(:http_post) { |_url, _body| response_or_lambda.call }
    else
      rpc.define_singleton_method(:http_post) { |_url, _body| response_or_lambda }
    end
  end
end
