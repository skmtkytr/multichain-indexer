# frozen_string_literal: true

require 'test_helper'

class TokenMetadataFetcherTest < ActiveSupport::TestCase
  setup do
    @chain_id = 1
    create_chain_config(chain_id: @chain_id)
    TokenContract.where(chain_id: @chain_id).delete_all
  end

  # --- KNOWN_TOKENS hardcoded decimals ---

  test 'KNOWN_TOKENS contains WETH with 18 decimals' do
    weth = TokenMetadataFetcher::KNOWN_TOKENS['0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2']
    assert_not_nil weth
    assert_equal 18, weth[:decimals]
    assert_equal 'WETH', weth[:symbol]
  end

  test 'KNOWN_TOKENS contains USDT with 6 decimals' do
    usdt = TokenMetadataFetcher::KNOWN_TOKENS['0xdac17f958d2ee523a2206206994597c13d831ec7']
    assert_not_nil usdt
    assert_equal 6, usdt[:decimals]
    assert_equal 'USDT', usdt[:symbol]
  end

  test 'KNOWN_TOKENS contains WBTC with 8 decimals' do
    wbtc = TokenMetadataFetcher::KNOWN_TOKENS['0x2260fac5e5542a773aa44fbcfedf7c193bc2c599']
    assert_not_nil wbtc
    assert_equal 8, wbtc[:decimals]
    assert_equal 'WBTC', wbtc[:symbol]
  end

  test 'KNOWN_TOKENS addresses are all lowercase' do
    TokenMetadataFetcher::KNOWN_TOKENS.each_key do |addr|
      assert_equal addr, addr.downcase, "Address #{addr} should be lowercase"
    end
  end

  # --- fetch_one with known token ---

  test 'fetch_one uses hardcoded decimals for known token' do
    addr = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
    TokenContract.create!(address: addr, chain_id: @chain_id, standard: 'erc20')

    token = TokenMetadataFetcher.fetch_one(chain_id: @chain_id, address: addr)
    assert_equal 18, token.decimals
    assert_equal 'WETH', token.symbol
  end

  test 'fetch_one preserves existing symbol for known token' do
    addr = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
    TokenContract.create!(address: addr, chain_id: @chain_id, standard: 'erc20', symbol: 'Wrapped Ether')

    token = TokenMetadataFetcher.fetch_one(chain_id: @chain_id, address: addr)
    assert_equal 18, token.decimals
    assert_equal 'Wrapped Ether', token.symbol
  end

  # --- fetch_one with RPC (dependency injection) ---

  test 'fetch_one calls RPC for unknown token' do
    addr = '0x' + 'ab' * 20
    TokenContract.create!(address: addr, chain_id: @chain_id, standard: 'erc20')

    fake_rpc = Object.new
    fake_rpc.define_singleton_method(:get_token_metadata) do |_a|
      { decimals: 9, symbol: 'TEST', name: 'Test Token' }
    end

    token = TokenMetadataFetcher.fetch_one(chain_id: @chain_id, address: addr, rpc: fake_rpc)
    assert_equal 9, token.decimals
    assert_equal 'TEST', token.symbol
    assert_equal 'Test Token', token.name
  end

  test 'fetch_one handles RPC returning nil decimals' do
    addr = '0x' + 'cd' * 20
    TokenContract.create!(address: addr, chain_id: @chain_id, standard: 'erc20')

    fake_rpc = Object.new
    fake_rpc.define_singleton_method(:get_token_metadata) { |_a| { decimals: nil, symbol: nil, name: nil } }

    token = TokenMetadataFetcher.fetch_one(chain_id: @chain_id, address: addr, rpc: fake_rpc)
    assert_nil token.decimals
  end

  # --- backfill ---

  test 'backfill updates known tokens without RPC' do
    addr = '0xdac17f958d2ee523a2206206994597c13d831ec7'
    TokenContract.create!(address: addr, chain_id: @chain_id, standard: 'erc20')

    fake_rpc = Object.new
    fake_rpc.define_singleton_method(:get_token_metadata) { |_a| raise 'Should not be called for known tokens' }

    result = TokenMetadataFetcher.backfill(chain_id: @chain_id, rpc: fake_rpc)
    assert_equal 1, result[:updated]

    token = TokenContract.find_by(address: addr, chain_id: @chain_id)
    assert_equal 6, token.decimals
    assert_equal 'USDT', token.symbol
  end

  test 'backfill skips tokens that already have decimals' do
    addr = '0x' + 'ee' * 20
    TokenContract.create!(address: addr, chain_id: @chain_id, standard: 'erc20', decimals: 18)

    fake_rpc = Object.new
    result = TokenMetadataFetcher.backfill(chain_id: @chain_id, rpc: fake_rpc)
    assert_equal 0, result[:total]
  end

  test 'backfill handles RPC errors gracefully' do
    addr = '0x' + 'ff' * 20
    TokenContract.create!(address: addr, chain_id: @chain_id, standard: 'erc20')

    fake_rpc = Object.new
    fake_rpc.define_singleton_method(:get_token_metadata) { |_a| raise StandardError, 'execution reverted' }

    result = TokenMetadataFetcher.backfill(chain_id: @chain_id, rpc: fake_rpc)
    assert_equal 0, result[:updated]
    assert_equal 1, result[:failed]
  end
end
