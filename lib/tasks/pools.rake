# frozen_string_literal: true

namespace :pools do
  desc 'Update dex_pools token0/token1 decimals from token_contracts'
  task update_decimals: :environment do
    updated = 0
    scope = DexPool.where(token0_decimals: nil).or(DexPool.where(token1_decimals: nil))
    total = scope.count
    puts "Updating decimals for #{total} pools..."

    scope.find_each(batch_size: 500) do |pool|
      changes = {}

      if pool.token0_decimals.nil?
        tc = TokenContract.find_by(address: pool.token0_address.downcase, chain_id: pool.chain_id)
        changes[:token0_decimals] = tc.decimals if tc&.decimals
      end

      if pool.token1_decimals.nil?
        tc = TokenContract.find_by(address: pool.token1_address.downcase, chain_id: pool.chain_id)
        changes[:token1_decimals] = tc.decimals if tc&.decimals
      end

      if changes.any?
        pool.update!(changes)
        updated += 1
      end
    end

    puts "Done. Updated #{updated}/#{total} pools."
  end
end
