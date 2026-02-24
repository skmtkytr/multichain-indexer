# frozen_string_literal: true

require 'temporalio/activity'

module Indexer
  class UtxoFetchBlockActivity < Temporalio::Activity::Definition
    def execute(params)
      action = params['action']
      chain_id = params['chain_id']

      case action
      when 'get_latest'
        config = ChainConfig.find_by(chain_id: chain_id)
        rpc = BitcoinRpc.new(chain_id: chain_id)
        tip = rpc.get_block_count
        confirmations = config&.confirmation_blocks || 6
        [tip - confirmations, 0].max

      when 'fetch_and_store'
        fetch_and_store(params)
      end
    end

    private

    def fetch_and_store(params)
      chain_id = params['chain_id']
      block_number = params['block_number']

      config = ChainConfig.find_by!(chain_id: chain_id)
      rpc = BitcoinRpc.new(chain_id: chain_id)

      # 1. Fetch block with verbosity=2 (full decoded txs)
      Temporalio::Activity::Context.current.heartbeat('rpc_fetch')
      block = rpc.get_block(block_number, verbosity: 2)
      return nil unless block

      txs = block['tx'] || []

      # 2. Store block
      Temporalio::Activity::Context.current.heartbeat('db_store')
      ActiveRecord::Base.transaction do
        IndexedBlock.upsert(
          {
            number: block['height'],
            block_hash: block['hash'],
            parent_hash: block['previousblockhash'] || '0' * 64,
            timestamp: block['time'],
            miner: extract_coinbase_address(txs.first, chain_id),
            gas_used: block['size'].to_s,       # repurpose: block size in bytes
            gas_limit: block['weight'].to_s,     # repurpose: block weight
            transaction_count: txs.size,
            chain_id: chain_id,
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: %i[chain_id number]
        )

        # 3. Process each transaction
        tx_records = []
        input_records = []
        output_records = []
        transfers = []

        txs.each do |tx|
          is_coinbase = tx['vin']&.first&.key?('coinbase')

          tx_records << {
            chain_id: chain_id,
            txid: tx['txid'],
            block_number: block['height'],
            block_hash: block['hash'],
            size: tx['size'],
            vsize: tx['vsize'],
            is_coinbase: is_coinbase,
            lock_time: tx['locktime'],
            input_count: (tx['vin'] || []).size,
            output_count: (tx['vout'] || []).size,
            created_at: Time.current,
            updated_at: Time.current
          }

          # Process outputs first (needed for input resolution within same block)
          (tx['vout'] || []).each do |vout|
            address = extract_address(vout)
            amount_satoshi = (BigDecimal(vout['value'].to_s) * 100_000_000).to_i
            script_type = vout.dig('scriptPubKey', 'type')

            # MWEB detection (Litecoin)
            is_mweb = script_type&.include?('mweb') || vout.dig('scriptPubKey', 'type') == 'witness_mweb_v0'
            is_confidential = is_mweb && address.nil?

            output_records << {
              chain_id: chain_id,
              txid: tx['txid'],
              vout_index: vout['n'],
              amount: amount_satoshi.to_s,
              script_pub_key: vout.dig('scriptPubKey', 'hex'),
              script_type: is_mweb ? 'mweb_pegin' : script_type,
              address: address,
              spent: false,
              is_confidential: is_confidential,
              created_at: Time.current,
              updated_at: Time.current
            }

            # Generate asset transfer for each output (except OP_RETURN)
            next if script_type == 'nulldata' || amount_satoshi.zero?

            transfer_type = if is_coinbase
                              'native' # coinbase reward
                            elsif is_confidential
                              'native'
                            else
                              'native'
                            end

            privacy_protocol = is_mweb ? 'mweb' : nil

            transfers << {
              tx_hash: tx['txid'],
              block_number: block['height'],
              chain_id: chain_id,
              transfer_type: transfer_type,
              token_address: nil,
              from_address: nil, # resolved later
              to_address: address,
              amount: amount_satoshi.to_s,
              token_id: nil,
              log_index: -1,
              trace_index: vout['n'],
              confidential: is_confidential,
              privacy_protocol: privacy_protocol,
              created_at: Time.current,
              updated_at: Time.current
            }
          end

          # Process inputs
          (tx['vin'] || []).each_with_index do |vin, idx|
            if vin['coinbase']
              input_records << {
                chain_id: chain_id,
                txid: tx['txid'],
                vin_index: idx,
                prev_txid: nil,
                prev_vout: nil,
                script_sig: vin['coinbase'],
                witness: vin['txinwitness'] || [],
                sequence: vin['sequence'],
                address: nil,
                amount: nil,
                is_coinbase: true,
                created_at: Time.current,
                updated_at: Time.current
              }
            else
              # Try resolving from already-processed outputs in this batch
              resolved = resolve_input_from_batch(output_records, vin, chain_id) ||
                         resolve_input_from_db(vin, chain_id)

              input_records << {
                chain_id: chain_id,
                txid: tx['txid'],
                vin_index: idx,
                prev_txid: vin['txid'],
                prev_vout: vin['vout'],
                script_sig: vin.dig('scriptSig', 'hex'),
                witness: vin['txinwitness'] || [],
                sequence: vin['sequence'],
                address: resolved&.dig(:address),
                amount: resolved&.dig(:amount)&.to_s,
                is_coinbase: false,
                created_at: Time.current,
                updated_at: Time.current
              }
            end
          end
        end

        # Bulk insert
        UtxoTransaction.upsert_all(tx_records, unique_by: %i[chain_id txid]) if tx_records.any?
        UtxoOutput.upsert_all(output_records, unique_by: %i[chain_id txid vout_index]) if output_records.any?
        UtxoInput.upsert_all(input_records, unique_by: %i[chain_id txid vin_index]) if input_records.any?

        # Mark spent outputs
        mark_spent_outputs(input_records, chain_id)

        # Resolve from_addresses in transfers using input data
        resolve_transfer_senders(transfers, txs, input_records, chain_id)

        # Store transfers
        if transfers.any?
          AssetTransfer.upsert_all(transfers, unique_by: %i[chain_id tx_hash transfer_type log_index trace_index])
        end
      end

      Rails.logger.info(
        "Indexed UTXO block ##{block['height']} on chain #{chain_id}: #{txs.size} txs"
      )

      {
        'block_number' => block['height'],
        'chain_id' => chain_id,
        'tx_count' => txs.size
      }
    end

    def extract_address(vout)
      spk = vout['scriptPubKey']
      return nil unless spk
      return spk['address'] if spk['address']
      addrs = spk['addresses']
      return addrs.first if addrs&.size == 1
      nil
    end

    def extract_coinbase_address(coinbase_tx, _chain_id)
      return nil unless coinbase_tx
      first_output = coinbase_tx['vout']&.first
      return nil unless first_output
      extract_address(first_output)
    end

    def resolve_input_from_batch(output_records, vin, chain_id)
      output_records.find do |o|
        o[:chain_id] == chain_id && o[:txid] == vin['txid'] && o[:vout_index] == vin['vout']
      end&.then do |o|
        { address: o[:address], amount: o[:amount].to_i }
      end
    end

    def resolve_input_from_db(vin, chain_id)
      output = UtxoOutput.find_by(
        chain_id: chain_id,
        txid: vin['txid'],
        vout_index: vin['vout']
      )
      return nil unless output
      { address: output.address, amount: output.amount.to_i }
    end

    def mark_spent_outputs(input_records, chain_id)
      input_records.each do |inp|
        next if inp[:is_coinbase] || inp[:prev_txid].nil?
        UtxoOutput.where(
          chain_id: chain_id,
          txid: inp[:prev_txid],
          vout_index: inp[:prev_vout]
        ).update_all(
          spent: true,
          spent_by_txid: inp[:txid],
          spent_by_vin: inp[:vin_index]
        )
      end
    end

    # For each transfer (output-based), find the input addresses that funded the tx
    def resolve_transfer_senders(transfers, txs, input_records, _chain_id)
      # Group inputs by txid to get sender addresses
      senders_by_txid = {}
      input_records.each do |inp|
        next if inp[:is_coinbase] || inp[:address].blank?
        senders_by_txid[inp[:txid]] ||= []
        senders_by_txid[inp[:txid]] << inp[:address]
      end

      transfers.each do |t|
        txid = t[:tx_hash]
        tx = txs.find { |tx_data| tx_data['txid'] == txid }
        if tx && tx['vin']&.first&.key?('coinbase')
          t[:from_address] = 'coinbase'
        else
          senders = senders_by_txid[txid]
          t[:from_address] = senders&.uniq&.first # primary sender (first input address)
        end
      end
    end
  end
end
