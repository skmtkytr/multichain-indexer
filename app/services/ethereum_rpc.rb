require "net/http"
require "json"

class EthereumRpc
  class RpcError < StandardError; end

  def initialize(rpc_url: nil, chain_id: nil)
    @chain_id = chain_id
    @rpc_url = if rpc_url
                 rpc_url
               elsif chain_id
                 config = ChainConfig.find_by(chain_id: chain_id)
                 config&.active_rpc_url || ENV.fetch("ETHEREUM_RPC_URL")
               else
                 ENV.fetch("ETHEREUM_RPC_URL")
               end
    @uri = URI(@rpc_url)
    @request_id = 0
  end

  def get_block_number
    result = call("eth_blockNumber")
    result.to_i(16)
  end

  def get_block_by_number(number, full_transactions: true)
    hex_number = number.is_a?(String) ? number : "0x#{number.to_s(16)}"
    call("eth_getBlockByNumber", [hex_number, full_transactions])
  end

  def get_transaction_receipt(tx_hash)
    call("eth_getTransactionReceipt", [tx_hash])
  end

  # Fetch all receipts for a block in one call (Geth ≥1.13, Erigon, most NaaS)
  def get_block_receipts(block_number)
    hex_number = block_number.is_a?(String) ? block_number : "0x#{block_number.to_s(16)}"
    call("eth_getBlockReceipts", [hex_number])
  end

  def get_logs(from_block:, to_block:, address: nil, topics: nil)
    filter = {
      fromBlock: "0x#{from_block.to_s(16)}",
      toBlock: "0x#{to_block.to_s(16)}"
    }
    filter[:address] = address if address
    filter[:topics] = topics if topics
    call("eth_getLogs", [filter])
  end

  # JSON-RPC batch: send multiple calls in one HTTP request
  def batch_call(requests)
    batch_body = requests.map do |req|
      @request_id += 1
      {
        jsonrpc: "2.0",
        method: req[:method],
        params: req[:params] || [],
        id: @request_id
      }
    end

    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = @uri.scheme == "https"
    http.read_timeout = 60

    request = Net::HTTP::Post.new(@uri.path.empty? ? "/" : @uri.path)
    request["Content-Type"] = "application/json"
    request.body = batch_body.to_json

    response = http.request(request)
    parsed = JSON.parse(response.body)

    # batch response is an array, sort by id to match request order
    parsed.sort_by { |r| r["id"] }.map do |r|
      raise RpcError, r["error"]["message"] if r["error"]
      r["result"]
    end
  end

  # Batch fetch receipts for multiple tx hashes
  def batch_get_transaction_receipts(tx_hashes)
    return [] if tx_hashes.empty?

    requests = tx_hashes.map do |hash|
      { method: "eth_getTransactionReceipt", params: [hash] }
    end
    batch_call(requests)
  end

  # Fetch block + receipts + logs in minimal RPC calls
  # Returns { block:, receipts:, logs: }
  def fetch_full_block(block_number, supports_block_receipts: true)
    block = get_block_by_number(block_number, full_transactions: true)
    return nil if block.nil?

    tx_hashes = (block["transactions"] || []).map { |tx| tx["hash"] }

    receipts = if supports_block_receipts
                 begin
                   get_block_receipts(block_number)
                 rescue RpcError => e
                   Rails.logger.warn("eth_getBlockReceipts failed for chain #{@chain_id}: #{e.message}, falling back to batch")
                   # Mark chain as not supporting block receipts
                   if @chain_id
                     ChainConfig.where(chain_id: @chain_id).update_all(supports_block_receipts: false)
                   end
                   batch_get_transaction_receipts(tx_hashes)
                 end
               else
                 batch_get_transaction_receipts(tx_hashes)
               end

    logs = get_logs(from_block: block_number, to_block: block_number)

    { "block" => block.merge("chain_id" => @chain_id), "receipts" => receipts || [], "logs" => logs || [] }
  end

  private

  def call(method, params = [])
    @request_id += 1
    body = {
      jsonrpc: "2.0",
      method: method,
      params: params,
      id: @request_id
    }.to_json

    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = @uri.scheme == "https"
    http.read_timeout = 30

    request = Net::HTTP::Post.new(@uri.path.empty? ? "/" : @uri.path)
    request["Content-Type"] = "application/json"
    request.body = body

    response = http.request(request)
    parsed = JSON.parse(response.body)

    raise RpcError, parsed["error"]["message"] if parsed["error"]

    parsed["result"]
  end
end
