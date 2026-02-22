# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Substrate RPC client using Sidecar REST API for block data
# and Substrate JSON-RPC for block height.
class SubstrateRpc
  class RpcError < StandardError; end

  def initialize(chain_id:)
    @chain_id = chain_id
    @config = ChainConfig.find_by!(chain_id: chain_id)
    @rpc_endpoints = @config.rpc_url_list  # Substrate JSON-RPC endpoints
    @sidecar_url = @config.sidecar_url
    raise "No RPC endpoints configured for chain #{chain_id}" if @rpc_endpoints.empty? && @sidecar_url.blank?
  end

  # Get latest finalized block number via Substrate JSON-RPC
  def get_block_number
    result = substrate_rpc_call('chain_getHeader')
    result['number'].to_i(16)
  end

  # Fetch full block data via Sidecar REST API (decoded extrinsics + events)
  def get_block(height)
    sidecar_get("/blocks/#{height}")
  end

  # Fetch block with events included (Sidecar includes them by default)
  def fetch_full_block(height)
    block = get_block(height)
    return nil unless block
    { 'block' => block }
  end

  private

  def sidecar_get(path)
    raise RpcError, "No Sidecar URL configured for chain #{@chain_id}" if @sidecar_url.blank?

    uri = URI("#{@sidecar_url.chomp('/')}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/json'

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      raise RpcError, "Sidecar HTTP #{response.code}: #{response.body&.truncate(200)}"
    end

    JSON.parse(response.body)
  end

  def substrate_rpc_call(method, params = [])
    last_error = nil

    @rpc_endpoints.each do |url|
      begin
        uri = URI(url)
        payload = {
          jsonrpc: '2.0',
          id: 1,
          method: method,
          params: params
        }.to_json

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request.body = payload

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise RpcError, "HTTP #{response.code}"
        end

        parsed = JSON.parse(response.body)
        raise RpcError, "RPC error: #{parsed['error']}" if parsed['error']
        return parsed['result']
      rescue => e
        last_error = e
        Rails.logger.warn("Substrate RPC #{method} failed on #{url}: #{e.message}")
      end
    end

    raise RpcError, "All RPC endpoints failed for #{method}: #{last_error&.message}"
  end
end
