# frozen_string_literal: true

desc 'Backfill token symbols for DexPool records missing them'
task backfill_pool_symbols: :environment do
  pools = DexPool.where(token0_symbol: nil).or(DexPool.where(token1_symbol: nil))
  total = pools.count
  puts "Backfilling symbols for #{total} pools..."

  updated = 0
  pools.find_each do |pool|
    rpc = EthereumRpc.new(chain_id: pool.chain_id)
    sym0, sym1 = Decoders::UniswapV2SwapDecoder.fetch_token_symbols(rpc, pool.token0_address, pool.token1_address)

    changes = {}
    changes[:token0_symbol] = sym0 if sym0 && pool.token0_symbol.nil?
    changes[:token1_symbol] = sym1 if sym1 && pool.token1_symbol.nil?

    if changes.any?
      pool.update!(changes)
      updated += 1
    end

    print '.' if updated % 10 == 0
  rescue => e
    puts "\nFailed for pool #{pool.pool_address}: #{e.message}"
  end

  puts "\nDone. Updated #{updated}/#{total} pools."
end
