require "net/http"
require "json"

class EthereumRpc
  class RpcError < StandardError; end
  class AllEndpointsFailedError < StandardError; end

  def initialize(rpc_url: nil, chain_id: nil)
    @chain_id = chain_id
    @rpc_urls = if rpc_url
                  [rpc_url]
                elsif chain_id
                  config = ChainConfig.find_by(chain_id: chain_id)
                  config&.rpc_url_list || [ENV.fetch("ETHEREUM_RPC_URL")]
                else
                  [ENV.fetch("ETHEREUM_RPC_URL")]
                end
    @current_index = 0
    @request_id = 0
  end

  def get_block_number
    result = call_with_fallback("eth_blockNumber")
    result.to_i(16)
  end

  def get_block_by_number(number, full_transactions: true)
    hex_number = number.is_a?(String) ? number : "0x#{number.to_s(16)}"
    call_with_fallback("eth_getBlockByNumber", [hex_number, full_transactions])
  end

  def get_transaction_receipt(tx_hash)
    call_with_fallback("eth_getTransactionReceipt", [tx_hash])
  end

  def get_block_receipts(block_number)
    hex_number = block_number.is_a?(String) ? block_number : "0x#{block_number.to_s(16)}"
    call_with_fallback("eth_getBlockReceipts", [hex_number])
  end

  def get_logs(from_block:, to_block:, address: nil, topics: nil)
    filter = {
      fromBlock: "0x#{from_block.to_s(16)}",
      toBlock: "0x#{to_block.to_s(16)}"
    }
    filter[:address] = address if address
    filter[:topics] = topics if topics
    call_with_fallback("eth_getLogs", [filter])
  end

  # JSON-RPC batch: send multiple calls in one HTTP request
  def batch_call(requests)
    batch_body = requests.map do |req|
      @request_id += 1
      { jsonrpc: "2.0", method: req[:method], params: req[:params] || [], id: @request_id }
    end

    response_body = http_post_with_fallback(batch_body.to_json)
    parsed = JSON.parse(response_body)

    parsed.sort_by { |r| r["id"] }.map do |r|
      raise RpcError, r["error"]["message"] if r["error"]
      r["result"]
    end
  end

  def batch_get_transaction_receipts(tx_hashes)
    return [] if tx_hashes.empty?
    requests = tx_hashes.map { |hash| { method: "eth_getTransactionReceipt", params: [hash] } }
    batch_call(requests)
  end

  def fetch_full_block(block_number, supports_block_receipts: true)
    block = get_block_by_number(block_number, full_transactions: true)
    return nil if block.nil?

    tx_hashes = (block["transactions"] || []).map { |tx| tx["hash"] }

    receipts = if supports_block_receipts
                 begin
                   get_block_receipts(block_number)
                 rescue RpcError => e
                   Rails.logger.warn("eth_getBlockReceipts failed for chain #{@chain_id}: #{e.message}, falling back to batch")
                   ChainConfig.where(chain_id: @chain_id).update_all(supports_block_receipts: false) if @chain_id
                   batch_get_transaction_receipts(tx_hashes)
                 end
               else
                 batch_get_transaction_receipts(tx_hashes)
               end

    # Extract logs from receipts instead of separate eth_getLogs call (saves 1 RPC call)
    logs = (receipts || []).flat_map { |r| r["logs"] || [] }

    { "block" => block.merge("chain_id" => @chain_id), "receipts" => receipts || [], "logs" => logs }
  end

  # Trace block for internal transactions
  def trace_block(block_number_hex, trace_method = nil)
    if trace_method.nil?
      trace_method = detect_trace_method(block_number_hex)
      if @chain_id && trace_method
        ChainConfig.where(chain_id: @chain_id).update_all(trace_method: trace_method, supports_trace: true)
      end
    end

    case trace_method
    when "debug_traceBlock"
      debug_trace_block(block_number_hex)
    when "trace_block"
      parity_trace_block(block_number_hex)
    else
      []
    end
  end

  # Get token metadata
  def get_token_metadata(contract_address)
    metadata = { name: nil, symbol: nil, decimals: nil, standard: "unknown" }

    begin
      raw = eth_call_function(contract_address, "06fdde03")
      metadata[:name] = decode_string_response(raw) if raw
    rescue => e
      Rails.logger.debug("Failed to get name for #{contract_address}: #{e.message}")
    end

    begin
      raw = eth_call_function(contract_address, "95d89b41")
      metadata[:symbol] = decode_string_response(raw) if raw
    rescue => e
      Rails.logger.debug("Failed to get symbol for #{contract_address}: #{e.message}")
    end

    begin
      raw = eth_call_function(contract_address, "313ce567")
      metadata[:decimals] = raw.to_i(16) if raw && raw != "0x"
    rescue => e
      Rails.logger.debug("Failed to get decimals for #{contract_address}: #{e.message}")
    end

    metadata[:standard] = detect_token_standard(contract_address)
    metadata
  end

  private

  # ---- Fallback logic ----

  # Single RPC call with automatic fallback across endpoints
  def call_with_fallback(method, params = [])
    last_error = nil
    tried = 0

    @rpc_urls.size.times do |offset|
      idx = (@current_index + offset) % @rpc_urls.size
      begin
        tried += 1
        result = call_single(@rpc_urls[idx], method, params)
        # Success — promote this endpoint
        @current_index = idx
        return result
      rescue RpcError => e
        # RPC-level error (method not found, etc.) — don't fallback, propagate
        raise
      rescue => e
        last_error = e
        Rails.logger.warn("RPC #{@rpc_urls[idx]} failed (#{method}): #{e.class} #{e.message}. Trying next endpoint...")
      end
    end

    raise AllEndpointsFailedError, "All #{tried} RPC endpoints failed for #{method}. Last error: #{last_error&.message}"
  end

  # HTTP POST with fallback (for batch calls)
  def http_post_with_fallback(body)
    last_error = nil

    @rpc_urls.size.times do |offset|
      idx = (@current_index + offset) % @rpc_urls.size
      begin
        result = http_post(@rpc_urls[idx], body)
        @current_index = idx
        return result
      rescue => e
        last_error = e
        Rails.logger.warn("RPC #{@rpc_urls[idx]} batch failed: #{e.class} #{e.message}. Trying next endpoint...")
      end
    end

    raise AllEndpointsFailedError, "All RPC endpoints failed for batch call. Last error: #{last_error&.message}"
  end

  # Single JSON-RPC call to a specific URL
  def call_single(rpc_url, method, params = [])
    @request_id += 1
    body = { jsonrpc: "2.0", method: method, params: params, id: @request_id }.to_json

    response_body = http_post(rpc_url, body)
    parsed = JSON.parse(response_body)

    raise RpcError, parsed["error"]["message"] if parsed["error"]
    parsed["result"]
  end

  # Raw HTTP POST
  def http_post(rpc_url, body)
    uri = URI(rpc_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 60
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri.path.empty? ? "/" : uri.path)
    request["Content-Type"] = "application/json"
    request.body = body

    response = http.request(request)
    response.body
  end

  # ---- Trace methods ----

  def detect_trace_method(block_number_hex)
    begin
      result = call_with_fallback("debug_traceBlockByNumber", [block_number_hex, {
        "tracer" => "callTracer",
        "tracerConfig" => { "onlyTopCall" => false }
      }])
      return "debug_traceBlock" if result
    rescue => e
      Rails.logger.debug("debug_traceBlockByNumber not supported: #{e.message}")
    end

    begin
      result = call_with_fallback("trace_block", [block_number_hex])
      return "trace_block" if result.is_a?(Array)
    rescue => e
      Rails.logger.debug("trace_block not supported: #{e.message}")
    end

    nil
  end

  def debug_trace_block(block_number_hex)
    result = call_with_fallback("debug_traceBlockByNumber", [block_number_hex, {
      "tracer" => "callTracer",
      "tracerConfig" => { "onlyTopCall" => false }
    }])

    traces = []
    result.each_with_index do |tx_trace, tx_index|
      next unless tx_trace["result"]
      extract_geth_calls(tx_trace["result"], tx_trace["txHash"], traces, 0)
    end
    traces
  end

  def parity_trace_block(block_number_hex)
    result = call_with_fallback("trace_block", [block_number_hex])
    result.select do |trace|
      trace.dig("action", "callType") == "call" &&
        trace.dig("action", "value") &&
        trace.dig("action", "value").to_i(16) > 0
    end
  end

  def extract_geth_calls(call_data, tx_hash, traces, depth)
    if call_data["type"] == "CALL" && call_data["value"] && call_data["value"].to_i(16) > 0
      traces << {
        "type" => "call",
        "from" => call_data["from"],
        "to" => call_data["to"],
        "value" => call_data["value"],
        "transactionHash" => tx_hash
      }
    end

    (call_data["calls"] || []).each do |subcall|
      extract_geth_calls(subcall, tx_hash, traces, depth + 1)
    end
  end

  # ---- Token metadata helpers ----

  def eth_call_function(to, data, from = nil)
    call_data = { to: to, data: "0x#{data}" }
    call_data[:from] = from if from
    call_with_fallback("eth_call", [call_data, "latest"])
  end

  def decode_string_response(hex_data)
    return nil if hex_data.nil? || hex_data == "0x"
    data = hex_data[2..]
    return nil if data.length < 128

    length = data[64, 64].to_i(16)
    return nil if length == 0 || length > 1000

    string_hex = data[128, length * 2]
    [string_hex].pack("H*").force_encoding("UTF-8").strip rescue nil
  end

  def detect_token_standard(contract_address)
    # ERC-721
    begin
      r = eth_call_function(contract_address, "01ffc9a780ac58cd00000000000000000000000000000000000000000000000000000000")
      return "erc721" if r && r[-1] == "1"
    rescue; end

    # ERC-1155
    begin
      r = eth_call_function(contract_address, "01ffc9a7d9b67a2600000000000000000000000000000000000000000000000000000000")
      return "erc1155" if r && r[-1] == "1"
    rescue; end

    # ERC-20 (has name + symbol)
    begin
      n = eth_call_function(contract_address, "06fdde03")
      s = eth_call_function(contract_address, "95d89b41")
      return "erc20" if n && n != "0x" && s && s != "0x"
    rescue; end

    "unknown"
  end
end
