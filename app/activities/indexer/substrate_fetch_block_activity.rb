# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  class SubstrateFetchBlockActivity < Temporalio::Activity::Definition
    # Transfer event mappings: pallet.method => handler
    TRANSFER_EVENTS = {
      'balances.Transfer' => :handle_balance_transfer,
      'assets.Transferred' => :handle_asset_transferred,
      'assets.Issued' => :handle_asset_issued,
      'assets.Burned' => :handle_asset_burned,
      'foreignAssets.Transferred' => :handle_foreign_asset_transferred,
      'nfts.Transferred' => :handle_nft_transferred
    }.freeze

    def execute(params)
      action = params['action']
      chain_id = params['chain_id']

      case action
      when 'get_latest'
        rpc = SubstrateRpc.new(chain_id: chain_id)
        rpc.get_block_number

      when 'fetch_and_store'
        fetch_and_store(params)
      end
    end

    private

    def fetch_and_store(params)
      chain_id = params['chain_id']
      block_number = params['block_number']

      rpc = SubstrateRpc.new(chain_id: chain_id)
      block_data = rpc.fetch_full_block(block_number)
      return nil unless block_data

      block = block_data['block']
      extrinsics = block['extrinsics'] || []

      # Collect all events globally for event_index tracking
      global_event_index = 0
      extrinsic_records = []
      event_records = []
      transfers = []

      ActiveRecord::Base.transaction do
        # Store block in indexed_blocks (reuse for unified dashboard)
        # Sidecar provides timestamp in first extrinsic (timestamp.set)
        timestamp = extract_timestamp(extrinsics)

        IndexedBlock.upsert(
          {
            number: block_number,
            block_hash: block['hash'] || '',
            parent_hash: block['parentHash'] || '',
            timestamp: timestamp || 0,
            miner: nil,  # no miner concept in substrate
            gas_used: nil,
            gas_limit: nil,
            transaction_count: extrinsics.count { |e| e.dig('signature', 'signer') },
            chain_id: chain_id,
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: %i[chain_id number]
        )

        extrinsics.each_with_index do |ext, ext_idx|
          method_info = ext['method'] || {}
          pallet = method_info['pallet'] || 'unknown'
          method = method_info['method'] || 'unknown'

          signature = ext['signature']
          signer = signature&.dig('signer', 'id') || signature&.dig('signer', 'Id')

          # Determine success from events
          events = ext['events'] || []
          success = events.any? { |e| e.dig('method', 'method') == 'ExtrinsicSuccess' }

          # Calculate fee from Withdraw event
          fee = extract_fee(events)

          extrinsic_records << {
            chain_id: chain_id,
            block_number: block_number,
            extrinsic_index: ext_idx,
            extrinsic_hash: ext['hash'],
            pallet: pallet,
            method: method,
            signer: signer,
            args: ext['args'] || {},
            success: success,
            fee: fee&.to_s,
            tip: (ext.dig('tip') || 0).to_s,
            created_at: Time.current,
            updated_at: Time.current
          }

          # Process events
          events.each do |event|
            event_method = event['method'] || {}
            event_pallet = event_method['pallet'] || 'unknown'
            event_name = event_method['method'] || 'unknown'
            event_data = event['data'] || {}

            event_records << {
              chain_id: chain_id,
              block_number: block_number,
              extrinsic_index: ext_idx,
              event_index: global_event_index,
              pallet: event_pallet,
              method: event_name,
              data: event_data,
              created_at: Time.current,
              updated_at: Time.current
            }

            # Extract asset transfers from events
            handler_key = "#{event_pallet}.#{event_name}"
            if TRANSFER_EVENTS.key?(handler_key)
              transfer = send(TRANSFER_EVENTS[handler_key], chain_id, block_number, ext, event_data, global_event_index)
              transfers << transfer if transfer
            end

            global_event_index += 1
          end
        end

        # Bulk insert
        SubstrateExtrinsic.upsert_all(extrinsic_records, unique_by: %i[chain_id block_number extrinsic_index]) if extrinsic_records.any?
        SubstrateEvent.upsert_all(event_records, unique_by: %i[chain_id block_number event_index]) if event_records.any?

        if transfers.any?
          AssetTransfer.upsert_all(transfers, unique_by: %i[chain_id tx_hash transfer_type log_index trace_index])
        end
      end

      user_exts = extrinsic_records.count { |e| e[:signer].present? }
      Rails.logger.info(
        "Indexed Substrate block ##{block_number} on chain #{chain_id}: " \
        "#{extrinsic_records.size} extrinsics (#{user_exts} signed), " \
        "#{event_records.size} events, #{transfers.size} transfers"
      )

      {
        'block_number' => block_number,
        'chain_id' => chain_id,
        'extrinsic_count' => extrinsic_records.size,
        'event_count' => event_records.size,
        'transfer_count' => transfers.size
      }
    end

    # --- Timestamp extraction ---

    def extract_timestamp(extrinsics)
      ts_ext = extrinsics.find { |e| e.dig('method', 'pallet') == 'timestamp' && e.dig('method', 'method') == 'set' }
      return nil unless ts_ext
      # Sidecar returns timestamp in args.now (milliseconds)
      now = ts_ext.dig('args', 'now') || ts_ext.dig('args', 'Now')
      now ? (now.to_i / 1000) : nil  # Convert ms to unix seconds
    end

    # --- Fee extraction ---

    def extract_fee(events)
      withdraw = events.find { |e| e.dig('method', 'pallet') == 'balances' && e.dig('method', 'method') == 'Withdraw' }
      return nil unless withdraw
      data = withdraw['data']
      # data can be array ["address", "amount"] or hash
      data.is_a?(Array) ? data[1].to_i : (data['amount'] || data['value']).to_i
    end

    # --- Transfer handlers ---

    def handle_balance_transfer(chain_id, block_number, ext, data, event_index)
      # data: ["from_address", "to_address", "amount"] or hash
      from, to, amount = if data.is_a?(Array)
                           [data[0], data[1], data[2]]
                         else
                           [data['from'], data['to'], data['amount'] || data['value']]
                         end
      return nil if amount.to_i.zero?

      {
        tx_hash: ext['hash'] || "substrate-#{block_number}-#{ext['index'] || 0}",
        block_number: block_number,
        chain_id: chain_id,
        transfer_type: 'native',
        token_address: nil,
        from_address: from,
        to_address: to,
        amount: amount.to_s,
        token_id: nil,
        log_index: event_index,
        trace_index: -1,
        confidential: false,
        privacy_protocol: nil,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    def handle_asset_transferred(chain_id, block_number, ext, data, event_index)
      asset_id, from, to, amount = if data.is_a?(Array)
                                     [data[0], data[1], data[2], data[3]]
                                   else
                                     [data['assetId'], data['from'], data['to'], data['amount']]
                                   end
      return nil if amount.to_i.zero?

      {
        tx_hash: ext['hash'] || "substrate-#{block_number}-#{ext['index'] || 0}",
        block_number: block_number,
        chain_id: chain_id,
        transfer_type: 'substrate_asset',
        token_address: asset_id.to_s,
        from_address: from,
        to_address: to,
        amount: amount.to_s,
        token_id: nil,
        log_index: event_index,
        trace_index: -1,
        confidential: false,
        privacy_protocol: nil,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    def handle_asset_issued(chain_id, block_number, ext, data, event_index)
      asset_id, owner, amount = if data.is_a?(Array)
                                  [data[0], data[1], data[2]]
                                else
                                  [data['assetId'], data['owner'], data['amount'] || data['totalSupply']]
                                end
      return nil if amount.to_i.zero?

      {
        tx_hash: ext['hash'] || "substrate-#{block_number}-#{ext['index'] || 0}",
        block_number: block_number,
        chain_id: chain_id,
        transfer_type: 'substrate_asset',
        token_address: asset_id.to_s,
        from_address: nil,  # mint
        to_address: owner,
        amount: amount.to_s,
        token_id: nil,
        log_index: event_index,
        trace_index: -1,
        confidential: false,
        privacy_protocol: nil,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    def handle_asset_burned(chain_id, block_number, ext, data, event_index)
      asset_id, owner, amount = if data.is_a?(Array)
                                  [data[0], data[1], data[2]]
                                else
                                  [data['assetId'], data['owner'], data['balance']]
                                end
      return nil if amount.to_i.zero?

      {
        tx_hash: ext['hash'] || "substrate-#{block_number}-#{ext['index'] || 0}",
        block_number: block_number,
        chain_id: chain_id,
        transfer_type: 'substrate_asset',
        token_address: asset_id.to_s,
        from_address: owner,
        to_address: nil,  # burn
        amount: amount.to_s,
        token_id: nil,
        log_index: event_index,
        trace_index: -1,
        confidential: false,
        privacy_protocol: nil,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    def handle_foreign_asset_transferred(chain_id, block_number, ext, data, event_index)
      asset_id, from, to, amount = if data.is_a?(Array)
                                     [data[0], data[1], data[2], data[3]]
                                   else
                                     [data['assetId'], data['from'], data['to'], data['amount']]
                                   end
      return nil if amount.to_i.zero?

      {
        tx_hash: ext['hash'] || "substrate-#{block_number}-#{ext['index'] || 0}",
        block_number: block_number,
        chain_id: chain_id,
        transfer_type: 'foreign_asset',
        token_address: asset_id.is_a?(Hash) ? asset_id.to_json : asset_id.to_s,
        from_address: from,
        to_address: to,
        amount: amount.to_s,
        token_id: nil,
        log_index: event_index,
        trace_index: -1,
        confidential: false,
        privacy_protocol: nil,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    def handle_nft_transferred(chain_id, block_number, ext, data, event_index)
      collection, item, from, to = if data.is_a?(Array)
                                     [data[0], data[1], data[2], data[3]]
                                   else
                                     [data['collection'], data['item'], data['from'], data['to']]
                                   end

      {
        tx_hash: ext['hash'] || "substrate-#{block_number}-#{ext['index'] || 0}",
        block_number: block_number,
        chain_id: chain_id,
        transfer_type: 'substrate_nft',
        token_address: collection.to_s,
        from_address: from,
        to_address: to,
        amount: '1',
        token_id: item.to_s,
        log_index: event_index,
        trace_index: -1,
        confidential: false,
        privacy_protocol: nil,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end
end
