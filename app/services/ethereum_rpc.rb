require "net/http"
require "json"

class EthereumRpc
  class RpcError < StandardError; end

  def initialize(rpc_url: nil)
    @rpc_url = rpc_url || ENV.fetch("ETHEREUM_RPC_URL")
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

  def get_logs(from_block:, to_block:, address: nil, topics: nil)
    filter = {
      fromBlock: "0x#{from_block.to_s(16)}",
      toBlock: "0x#{to_block.to_s(16)}"
    }
    filter[:address] = address if address
    filter[:topics] = topics if topics
    call("eth_getLogs", [filter])
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
