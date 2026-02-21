ChainConfig::DEFAULTS.each do |chain_id, attrs|
  ChainConfig.find_or_create_by!(chain_id: chain_id) do |c|
    c.assign_attributes(attrs)
    puts "  Created chain config: #{attrs[:name]} (#{chain_id})"
  end
end

puts "Seed complete: #{ChainConfig.count} chains configured"
