# frozen_string_literal: true

# Bitcoin Core compatible JSON-RPC client.
# Works with Bitcoin, Litecoin, Dogecoin, Bitcoin Cash, Dash, Zcash etc.
class BitcoinRpc
  class RpcError < StandardError; end

  def initialize(chain_id:)
    @chain_id = chain_id
    @config = ChainConfig.find_by!(chain_id: chain_id)
    @endpoints = @config.rpc_url_list
    raise "No RPC endpoints configured for chain #{chain_id}" if @endpoints.empty?
  end

  # Get current block count (height)
  def get_block_count
    call('getblockcount')
  end

  # Get block hash at height
  def get_block_hash(height)
    call('getblockhash', [height])
  end

  # Get block with full transaction data
  # verbosity: 0=hex, 1=json, 2=json+decoded tx
  def get_block(hash_or_height, verbosity: 2)
    block_hash = if hash_or_height.is_a?(Integer)
                   get_block_hash(hash_or_height)
                 else
                   hash_or_height
                 end
    call('getblock', [block_hash, verbosity])
  end

  # Get decoded raw transaction
  def get_raw_transaction(txid, verbose: true)
    call('getrawtransaction', [txid, verbose])
  end

  # Get blockchain info (chain, blocks, difficulty, etc.)
  def get_blockchain_info
    call('getblockchaininfo')
  end

  # Fetch a full block with all tx data resolved
  # Returns { block: {}, transactions: [] }
  def fetch_full_block(height)
    block = get_block(height, verbosity: 2)
    return nil unless block

    {
      'block' => block,
      'transactions' => block['tx'] || []
    }
  end

  # Resolve input addresses/amounts from previous outputs.
  # For inputs referencing txs already in our DB, use DB lookup.
  # Otherwise fetch via RPC.
  def resolve_inputs(inputs, chain_id)
    inputs.map do |input|
      next input if input['coinbase'] # coinbase input has no prev tx

      prev_txid = input['txid']
      prev_vout = input['vout']
      next input unless prev_txid && prev_vout

      # Try DB first
      cached_output = UtxoOutput.find_by(
        chain_id: chain_id,
        txid: prev_txid,
        vout_index: prev_vout
      )

      if cached_output
        input.merge(
          '_resolved_address' => cached_output.address,
          '_resolved_amount' => cached_output.amount.to_i
        )
      else
        # Fetch from RPC
        begin
          prev_tx = get_raw_transaction(prev_txid)
          if prev_tx && prev_tx['vout'] && prev_tx['vout'][prev_vout]
            vout = prev_tx['vout'][prev_vout]
            address = extract_address(vout)
            amount_satoshi = (BigDecimal(vout['value'].to_s) * 100_000_000).to_i
            input.merge(
              '_resolved_address' => address,
              '_resolved_amount' => amount_satoshi
            )
          else
            input
          end
        rescue => e
          Rails.logger.warn("Failed to resolve input #{prev_txid}:#{prev_vout}: #{e.message}")
          input
        end
      end
    end
  end

  private

  def call(method, params = [])
    call_with_fallback(method, params)
  end

  def call_with_fallback(method, params)
    last_error = nil

    @endpoints.each do |url|
      begin
        result = rpc_request(url, method, params)
        return result
      rescue => e
        last_error = e
        Rails.logger.warn("Bitcoin RPC #{method} failed on #{mask_url(url)}: #{e.message}")
      end
    end

    raise RpcError, "All RPC endpoints failed for #{method}: #{last_error&.message}"
  end

  def rpc_request(url, method, params)
    uri = URI(url)
    payload = {
      jsonrpc: '1.0',
      id: "indexer-#{SecureRandom.hex(4)}",
      method: method,
      params: params
    }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'

    # Bitcoin RPC auth (user:password in URL)
    if uri.user && uri.password
      request.basic_auth(uri.user, uri.password)
    end

    request.body = payload
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise RpcError, "HTTP #{response.code}: #{response.body&.truncate(200)}"
    end

    parsed = JSON.parse(response.body)
    raise RpcError, "RPC error: #{parsed['error']}" if parsed['error']

    parsed['result']
  end

  def extract_address(vout)
    spk = vout['scriptPubKey']
    return nil unless spk

    # Bitcoin Core >= 22 uses 'address' field directly
    return spk['address'] if spk['address']

    # Older versions use 'addresses' array
    addrs = spk['addresses']
    return addrs.first if addrs&.size == 1

    nil
  end

  def mask_url(url)
    uri = URI(url)
    masked = "#{uri.scheme}://#{uri.host}"
    masked += ":#{uri.port}" unless [80, 443].include?(uri.port)
    masked
  end
end
