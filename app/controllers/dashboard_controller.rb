class DashboardController < ApplicationController
  def index
    chain_id = params.fetch(:chain_id, 1).to_i
    @cursor = IndexerCursor.find_by(chain_id: chain_id)
    @blocks = IndexedBlock.by_chain(chain_id).recent.limit(20)
    @transactions = IndexedTransaction.by_chain(chain_id).order(block_number: :desc, tx_index: :asc).limit(20)
    @logs = IndexedLog.by_chain(chain_id).order(block_number: :desc, log_index: :asc).limit(20)

    @stats = {
      chain_id: chain_id,
      status: @cursor&.status || "not_initialized",
      last_indexed_block: @cursor&.last_indexed_block || 0,
      error: @cursor&.error_message,
      blocks_count: IndexedBlock.by_chain(chain_id).count,
      transactions_count: IndexedTransaction.by_chain(chain_id).count,
      logs_count: IndexedLog.by_chain(chain_id).count
    }

    render html: build_html.html_safe, layout: false
  end

  private

  def build_html
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>EVM Indexer Dashboard</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; background: #0d1117; color: #c9d1d9; }
          .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
          h1 { color: #58a6ff; margin-bottom: 8px; font-size: 24px; }
          h2 { color: #8b949e; font-size: 16px; margin-bottom: 20px; }
          h3 { color: #58a6ff; font-size: 16px; margin-bottom: 12px; }

          .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 32px; }
          .stat-card {
            background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px;
          }
          .stat-label { color: #8b949e; font-size: 12px; text-transform: uppercase; letter-spacing: 1px; }
          .stat-value { color: #f0f6fc; font-size: 28px; font-weight: 700; margin-top: 4px; }
          .stat-value.running { color: #3fb950; }
          .stat-value.stopped { color: #f85149; }
          .stat-value.not_initialized { color: #8b949e; }

          .controls { margin-bottom: 32px; display: flex; gap: 12px; align-items: center; }
          .btn {
            padding: 8px 20px; border: none; border-radius: 6px; cursor: pointer;
            font-size: 14px; font-weight: 600; transition: opacity 0.2s;
          }
          .btn:hover { opacity: 0.85; }
          .btn-start { background: #238636; color: #fff; }
          .btn-stop { background: #da3633; color: #fff; }
          .btn-refresh { background: #30363d; color: #c9d1d9; }
          .btn:disabled { opacity: 0.4; cursor: not-allowed; }
          #control-msg { color: #8b949e; font-size: 13px; }

          .section { margin-bottom: 32px; }
          table { width: 100%; border-collapse: collapse; background: #161b22; border: 1px solid #30363d; border-radius: 8px; overflow: hidden; }
          th { background: #21262d; color: #8b949e; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; padding: 10px 12px; text-align: left; }
          td { padding: 8px 12px; border-top: 1px solid #21262d; font-size: 13px; font-family: 'SF Mono', 'Cascadia Code', monospace; }
          tr:hover td { background: #1c2128; }
          .hash { color: #58a6ff; }
          .addr { color: #d2a8ff; }
          .num { color: #79c0ff; }
          .empty { color: #484f58; text-align: center; padding: 40px; }

          .chain-select { display: flex; gap: 8px; margin-bottom: 20px; }
          .chain-btn { padding: 4px 12px; background: #21262d; color: #8b949e; border: 1px solid #30363d; border-radius: 20px; cursor: pointer; font-size: 12px; }
          .chain-btn.active { background: #388bfd26; color: #58a6ff; border-color: #388bfd; }

          .topbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; }
          .links a { color: #58a6ff; text-decoration: none; font-size: 13px; margin-left: 16px; }
          .links a:hover { text-decoration: underline; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="topbar">
            <div>
              <h1>⛓ EVM Indexer</h1>
              <h2>Temporal + Rails Blockchain Indexer</h2>
            </div>
            <div class="links">
              <a href="http://localhost:8080" target="_blank">Temporal UI ↗</a>
              <a href="/api/v1/indexer/status?chain_id=#{@stats[:chain_id]}">API Status ↗</a>
              <a href="/api/v1/blocks">API Blocks ↗</a>
            </div>
          </div>

          <div class="chain-select">
            #{chain_buttons}
          </div>

          <div class="stats-grid">
            <div class="stat-card">
              <div class="stat-label">Status</div>
              <div class="stat-value #{@stats[:status]}">#{@stats[:status].upcase}</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">Last Block</div>
              <div class="stat-value">#{format_number(@stats[:last_indexed_block])}</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">Blocks Indexed</div>
              <div class="stat-value">#{format_number(@stats[:blocks_count])}</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">Transactions</div>
              <div class="stat-value">#{format_number(@stats[:transactions_count])}</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">Event Logs</div>
              <div class="stat-value">#{format_number(@stats[:logs_count])}</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">Chain ID</div>
              <div class="stat-value">#{@stats[:chain_id]}</div>
            </div>
          </div>

          #{error_banner}

          <div class="controls">
            <button class="btn btn-start" onclick="controlIndexer('start')" #{@cursor&.running? ? 'disabled' : ''}>▶ Start Indexer</button>
            <button class="btn btn-stop" onclick="controlIndexer('stop')" #{!@cursor&.running? ? 'disabled' : ''}>⏹ Stop Indexer</button>
            <button class="btn btn-refresh" onclick="location.reload()">↻ Refresh</button>
            <span id="control-msg"></span>
          </div>

          <div class="section">
            <h3>Recent Blocks</h3>
            #{blocks_table}
          </div>

          <div class="section">
            <h3>Recent Transactions</h3>
            #{transactions_table}
          </div>

          <div class="section">
            <h3>Recent Event Logs</h3>
            #{logs_table}
          </div>
        </div>

        <script>
          async function controlIndexer(action) {
            const msg = document.getElementById('control-msg');
            msg.textContent = 'Processing...';
            try {
              const res = await fetch('/api/v1/indexer/' + action + '?chain_id=#{@stats[:chain_id]}', { method: 'POST' });
              const data = await res.json();
              msg.textContent = JSON.stringify(data);
              setTimeout(() => location.reload(), 1500);
            } catch(e) {
              msg.textContent = 'Error: ' + e.message;
            }
          }

          // Auto-refresh every 10s
          setTimeout(() => location.reload(), 10000);
        </script>
      </body>
      </html>
    HTML
  end

  def chain_buttons
    chains = { 1 => "Ethereum", 137 => "Polygon", 42161 => "Arbitrum", 10 => "Optimism", 8453 => "Base" }
    current = @stats[:chain_id]
    chains.map do |id, name|
      active = id == current ? "active" : ""
      %(<a class="chain-btn #{active}" href="/?chain_id=#{id}">#{name} (#{id})</a>)
    end.join
  end

  def error_banner
    return "" unless @cursor&.error_message.present?
    %(<div style="background:#f8514926;border:1px solid #f85149;border-radius:8px;padding:12px 16px;margin-bottom:20px;color:#f85149;font-size:13px;">⚠️ #{ERB::Util.html_escape(@cursor.error_message)}</div>)
  end

  def blocks_table
    return %(<div class="empty">No blocks indexed yet</div>) if @blocks.empty?

    rows = @blocks.map do |b|
      <<~ROW
        <tr>
          <td class="num">#{b.number}</td>
          <td class="hash">#{truncate_hash(b.block_hash)}</td>
          <td>#{Time.at(b.timestamp).utc.strftime('%Y-%m-%d %H:%M:%S')}</td>
          <td class="addr">#{truncate_hash(b.miner)}</td>
          <td class="num">#{b.transaction_count}</td>
          <td class="num">#{format_number(b.gas_used)}</td>
        </tr>
      ROW
    end.join

    <<~TABLE
      <table>
        <thead><tr><th>Block</th><th>Hash</th><th>Timestamp</th><th>Miner</th><th>Txns</th><th>Gas Used</th></tr></thead>
        <tbody>#{rows}</tbody>
      </table>
    TABLE
  end

  def transactions_table
    return %(<div class="empty">No transactions indexed yet</div>) if @transactions.empty?

    rows = @transactions.map do |tx|
      <<~ROW
        <tr>
          <td class="hash">#{truncate_hash(tx.tx_hash)}</td>
          <td class="num">#{tx.block_number}</td>
          <td class="addr">#{truncate_hash(tx.from_address)}</td>
          <td class="addr">#{truncate_hash(tx.to_address)}</td>
          <td class="num">#{format_wei(tx.value)}</td>
          <td>#{tx.status == 1 ? '✅' : '❌'}</td>
        </tr>
      ROW
    end.join

    <<~TABLE
      <table>
        <thead><tr><th>Tx Hash</th><th>Block</th><th>From</th><th>To</th><th>Value (ETH)</th><th>Status</th></tr></thead>
        <tbody>#{rows}</tbody>
      </table>
    TABLE
  end

  def logs_table
    return %(<div class="empty">No event logs indexed yet</div>) if @logs.empty?

    rows = @logs.map do |log|
      <<~ROW
        <tr>
          <td class="num">#{log.block_number}</td>
          <td class="hash">#{truncate_hash(log.tx_hash)}</td>
          <td class="addr">#{truncate_hash(log.address)}</td>
          <td class="hash">#{truncate_hash(log.topic0)}</td>
          <td class="num">#{log.log_index}</td>
        </tr>
      ROW
    end.join

    <<~TABLE
      <table>
        <thead><tr><th>Block</th><th>Tx Hash</th><th>Contract</th><th>Event (topic0)</th><th>Index</th></tr></thead>
        <tbody>#{rows}</tbody>
      </table>
    TABLE
  end

  def truncate_hash(hash)
    return "—" if hash.blank?
    "#{hash[0..7]}...#{hash[-6..]}"
  end

  def format_number(num)
    return "0" if num.nil? || num == 0
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def format_wei(wei)
    return "0" if wei.nil? || wei == 0
    eth = wei.to_f / 1e18
    eth < 0.0001 ? "< 0.0001" : "%.4f" % eth
  end
end
