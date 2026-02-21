# frozen_string_literal: true

# Event signature seeds for common token transfer events

event_signatures = [
  {
    signature_hash: '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef',
    event_name: 'Transfer',
    full_signature: 'Transfer(address,address,uint256)',
    abi_json: {
      'name' => 'Transfer',
      'type' => 'event',
      'anonymous' => false,
      'inputs' => [
        { 'indexed' => true, 'name' => 'from', 'type' => 'address' },
        { 'indexed' => true, 'name' => 'to', 'type' => 'address' },
        { 'indexed' => false, 'name' => 'value', 'type' => 'uint256' }
      ]
    }
  },
  {
    signature_hash: '0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925',
    event_name: 'Approval',
    full_signature: 'Approval(address,address,uint256)',
    abi_json: {
      'name' => 'Approval',
      'type' => 'event',
      'anonymous' => false,
      'inputs' => [
        { 'indexed' => true, 'name' => 'owner', 'type' => 'address' },
        { 'indexed' => true, 'name' => 'spender', 'type' => 'address' },
        { 'indexed' => false, 'name' => 'value', 'type' => 'uint256' }
      ]
    }
  },
  {
    signature_hash: '0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62',
    event_name: 'TransferSingle',
    full_signature: 'TransferSingle(address,address,address,uint256,uint256)',
    abi_json: {
      'name' => 'TransferSingle',
      'type' => 'event',
      'anonymous' => false,
      'inputs' => [
        { 'indexed' => true, 'name' => 'operator', 'type' => 'address' },
        { 'indexed' => true, 'name' => 'from', 'type' => 'address' },
        { 'indexed' => true, 'name' => 'to', 'type' => 'address' },
        { 'indexed' => false, 'name' => 'id', 'type' => 'uint256' },
        { 'indexed' => false, 'name' => 'value', 'type' => 'uint256' }
      ]
    }
  },
  {
    signature_hash: '0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb',
    event_name: 'TransferBatch',
    full_signature: 'TransferBatch(address,address,address,uint256[],uint256[])',
    abi_json: {
      'name' => 'TransferBatch',
      'type' => 'event',
      'anonymous' => false,
      'inputs' => [
        { 'indexed' => true, 'name' => 'operator', 'type' => 'address' },
        { 'indexed' => true, 'name' => 'from', 'type' => 'address' },
        { 'indexed' => true, 'name' => 'to', 'type' => 'address' },
        { 'indexed' => false, 'name' => 'ids', 'type' => 'uint256[]' },
        { 'indexed' => false, 'name' => 'values', 'type' => 'uint256[]' }
      ]
    }
  },
  {
    signature_hash: '0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c',
    event_name: 'Deposit',
    full_signature: 'Deposit(address,uint256)',
    abi_json: {
      'name' => 'Deposit',
      'type' => 'event',
      'anonymous' => false,
      'inputs' => [
        { 'indexed' => true, 'name' => 'dst', 'type' => 'address' },
        { 'indexed' => false, 'name' => 'wad', 'type' => 'uint256' }
      ]
    }
  },
  {
    signature_hash: '0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65',
    event_name: 'Withdrawal',
    full_signature: 'Withdrawal(address,uint256)',
    abi_json: {
      'name' => 'Withdrawal',
      'type' => 'event',
      'anonymous' => false,
      'inputs' => [
        { 'indexed' => true, 'name' => 'src', 'type' => 'address' },
        { 'indexed' => false, 'name' => 'wad', 'type' => 'uint256' }
      ]
    }
  }
]

puts 'Seeding event signatures...'

event_signatures.each do |sig|
  EventSignature.find_or_create_by!(signature_hash: sig[:signature_hash]) do |event_sig|
    event_sig.event_name = sig[:event_name]
    event_sig.full_signature = sig[:full_signature]
    event_sig.abi_json = sig[:abi_json]
  end
  puts "  Created/updated: #{sig[:event_name]} (#{sig[:signature_hash]})"
end

puts 'Event signatures seeded successfully!'
