# frozen_string_literal: true

namespace :tokens do
  desc 'Fetch decimals and symbol for tokens missing metadata'
  task :fetch_metadata, [:chain_id] => :environment do |_t, args|
    chain_id = (args[:chain_id] || 1).to_i
    puts "Fetching token metadata for chain #{chain_id}..."
    result = TokenMetadataFetcher.backfill(chain_id: chain_id)
    puts "\nResults: updated=#{result[:updated]} failed=#{result[:failed]} total=#{result[:total]}"
  end
end
