# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @chain_configs = ChainConfig.order(:chain_id)
    chain_id = params.fetch(:chain_id, @chain_configs.first&.chain_id || 1).to_i
    @current_chain = @chain_configs.find { |c| c.chain_id == chain_id } || @chain_configs.first
    @explorer = @current_chain&.explorer_url&.chomp('/')
    @cursor = IndexerCursor.find_by(chain_id: chain_id)
    @blocks = IndexedBlock.by_chain(chain_id).recent.limit(20)
    @transactions = IndexedTransaction.by_chain(chain_id).order(block_number: :desc, tx_index: :asc).limit(20)
    @logs = IndexedLog.by_chain(chain_id).order(block_number: :desc, log_index: :asc).limit(20)
    @asset_transfers = AssetTransfer.by_chain(chain_id).recent.limit(20)
    @token_contracts = TokenContract.by_chain(chain_id).limit(20)

    @dex_swaps = DexSwap.where(chain_id: chain_id).order(id: :desc).limit(20)
    @arb_opportunities = ArbOpportunity.where(chain_id: chain_id).order(id: :desc).limit(20)
    @dex_pools_count = DexPool.where(chain_id: chain_id).count

    @stats = {
      chain_id: chain_id,
      status: @cursor&.status || 'not_initialized',
      last_indexed_block: @cursor&.last_indexed_block || 0,
      error: @cursor&.error_message,
      blocks_count: fast_count('indexed_blocks', chain_id),
      transactions_count: fast_count('indexed_transactions', chain_id),
      logs_count: fast_count('indexed_logs', chain_id),
      transfers_count: fast_count('asset_transfers', chain_id),
      tokens_count: fast_count('token_contracts', chain_id),
      swaps_count: fast_count('dex_swaps', chain_id),
      arb_count: fast_count('arb_opportunities', chain_id),
      pools_count: @dex_pools_count
    }

    @page = params.fetch(:page, 'overview')

    render html: build_html.html_safe, layout: false
  end

  private

  # Use partial index scan or estimated count for large tables
  def fast_count(table_name, chain_id)
    sql = "SELECT count_estimate('SELECT 1 FROM #{table_name} WHERE chain_id = #{chain_id.to_i}')"
    ActiveRecord::Base.connection.execute(sql).first['count_estimate'].to_i
  rescue ActiveRecord::StatementInvalid
    # Fallback: use pg_stat estimate if function doesn't exist
    ActiveRecord::Base.connection.execute(
      "SELECT COUNT(*) AS cnt FROM #{table_name} WHERE chain_id = #{chain_id.to_i}"
    ).first['cnt'].to_i
  end

  def build_html
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>EVM Indexer Dashboard</title>
        <style>#{css}</style>
      </head>
      <body>
        <div class="layout">
          #{sidebar}
          <main class="main">
            #{
              case @page
              when 'chains' then chains_page
              when 'transfers' then transfers_page
              when 'tokens' then tokens_page
              when 'address' then address_page
              when 'webhooks' then webhooks_page
              when 'dex' then dex_page
              else overview_page
              end
            }
          </main>
        </div>
        <script>#{javascript}</script>
      </body>
      </html>
    HTML
  end

  def css
    <<~CSS
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; background: #0d1117; color: #c9d1d9; }
      .layout { display: flex; min-height: 100vh; }

      /* Sidebar */
      .sidebar { width: 240px; background: #161b22; border-right: 1px solid #30363d; padding: 20px 0; flex-shrink: 0; }
      .sidebar-brand { padding: 0 16px 20px; border-bottom: 1px solid #30363d; margin-bottom: 12px; }
      .sidebar-brand h1 { color: #58a6ff; font-size: 18px; }
      .sidebar-brand p { color: #484f58; font-size: 11px; margin-top: 2px; }
      .nav-section { padding: 8px 12px; color: #484f58; font-size: 10px; text-transform: uppercase; letter-spacing: 1.5px; margin-top: 8px; }
      .nav-item { display: flex; align-items: center; gap: 8px; padding: 6px 16px; color: #8b949e; text-decoration: none; font-size: 13px; transition: all 0.15s; cursor: pointer; }
      .nav-item:hover { background: #1c2128; color: #c9d1d9; }
      .nav-item.active { background: #388bfd15; color: #58a6ff; border-right: 2px solid #58a6ff; }
      .nav-chain { display: flex; align-items: center; justify-content: space-between; padding: 5px 16px; color: #8b949e; text-decoration: none; font-size: 12px; }
      .nav-chain:hover { background: #1c2128; color: #c9d1d9; }
      .nav-chain.active { background: #388bfd15; color: #58a6ff; }
      .nav-chain .dot { width: 6px; height: 6px; border-radius: 50%; }
      .dot.running { background: #3fb950; }
      .dot.stopped { background: #f85149; }
      .dot.not_initialized { background: #484f58; }
      .dot.error { background: #d29922; }
      .nav-chain-name { display: flex; align-items: center; gap: 8px; }
      .external-link { margin-top: auto; border-top: 1px solid #30363d; padding-top: 12px; }

      /* Main */
      .main { flex: 1; padding: 24px 32px; overflow-y: auto; }
      .page-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; }
      .page-title { color: #f0f6fc; font-size: 20px; font-weight: 600; }
      .page-subtitle { color: #8b949e; font-size: 13px; margin-top: 2px; }
      h3 { color: #58a6ff; font-size: 15px; margin-bottom: 12px; }

      /* Stats */
      .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 28px; }
      .stat-card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; }
      .stat-label { color: #8b949e; font-size: 11px; text-transform: uppercase; letter-spacing: 0.8px; }
      .stat-value { color: #f0f6fc; font-size: 24px; font-weight: 700; margin-top: 2px; }
      .stat-value.running { color: #3fb950; }
      .stat-value.stopped { color: #f85149; }
      .stat-value.not_initialized { color: #8b949e; }
      .stat-value.error { color: #d29922; }

      /* Controls */
      .controls { margin-bottom: 24px; display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
      .btn { padding: 7px 16px; border: none; border-radius: 6px; cursor: pointer; font-size: 13px; font-weight: 600; transition: all 0.15s; }
      .btn:hover { opacity: 0.85; }
      .btn-sm { padding: 4px 10px; font-size: 12px; }
      .btn-start { background: #238636; color: #fff; }
      .btn-stop { background: #da3633; color: #fff; }
      .btn-refresh { background: #30363d; color: #c9d1d9; }
      .btn-primary { background: #388bfd; color: #fff; }
      .btn-outline { background: transparent; color: #8b949e; border: 1px solid #30363d; }
      .btn-outline:hover { color: #c9d1d9; border-color: #8b949e; }
      .btn-danger { background: transparent; color: #f85149; border: 1px solid #f8514930; }
      .btn-danger:hover { background: #f8514915; }
      .btn-test { background: #1f6feb; color: #fff; }
      .btn:disabled { opacity: 0.4; cursor: not-allowed; }
      #control-msg { color: #8b949e; font-size: 12px; max-width: 400px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

      /* Tables */
      .section { margin-bottom: 28px; }
      table { width: 100%; border-collapse: collapse; background: #161b22; border: 1px solid #30363d; border-radius: 8px; overflow: hidden; font-size: 12px; }
      th { background: #21262d; color: #8b949e; font-size: 10px; text-transform: uppercase; letter-spacing: 0.8px; padding: 8px 10px; text-align: left; }
      td { padding: 7px 10px; border-top: 1px solid #21262d; font-family: 'SF Mono', 'Cascadia Code', Consolas, monospace; }
      tr:hover td { background: #1c2128; }
      .hash { color: #58a6ff; text-decoration: none; }
      .addr { color: #d2a8ff; text-decoration: none; }
      .num { color: #79c0ff; text-decoration: none; }
      a.hash:hover, a.addr:hover, a.num:hover { text-decoration: underline; opacity: 0.85; }
      .empty { color: #484f58; text-align: center; padding: 40px; background: #161b22; border: 1px solid #30363d; border-radius: 8px; }

      /* Chain config cards */
      .chain-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 16px; margin-bottom: 24px; }
      .chain-card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; position: relative; }
      .chain-card.disabled { opacity: 0.5; }
      .chain-card-header { display: flex; justify-content: space-between; align-items: start; margin-bottom: 12px; }
      .chain-card-title { font-size: 15px; font-weight: 600; color: #f0f6fc; }
      .chain-card-id { font-size: 11px; color: #484f58; margin-top: 2px; }
      .chain-card-badge { padding: 2px 8px; border-radius: 12px; font-size: 10px; font-weight: 600; text-transform: uppercase; }
      .badge-enabled { background: #23863615; color: #3fb950; border: 1px solid #23863640; }
      .badge-disabled { background: #f8514915; color: #f85149; border: 1px solid #f8514940; }
      .badge-mainnet { background: #388bfd15; color: #58a6ff; border: 1px solid #388bfd40; }
      .badge-testnet { background: #d2992215; color: #d29922; border: 1px solid #d2992240; }
      .badge-devnet { background: #8b949e15; color: #8b949e; border: 1px solid #8b949e40; }
      .chain-card-body { font-size: 12px; color: #8b949e; }
      .chain-card-row { display: flex; justify-content: space-between; padding: 4px 0; border-bottom: 1px solid #21262d; }
      .chain-card-row:last-child { border-bottom: none; }
      .chain-card-label { color: #484f58; }
      .chain-card-value { color: #c9d1d9; font-family: 'SF Mono', Consolas, monospace; font-size: 11px; max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .chain-card-actions { display: flex; gap: 6px; margin-top: 12px; }

      /* Modal */
      .modal-overlay { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: #0d1117cc; z-index: 100; align-items: center; justify-content: center; }
      .modal-overlay.show { display: flex; }
      .modal { background: #161b22; border: 1px solid #30363d; border-radius: 12px; width: 480px; max-height: 90vh; overflow-y: auto; }
      .modal-header { padding: 16px 20px; border-bottom: 1px solid #30363d; display: flex; justify-content: space-between; align-items: center; }
      .modal-title { font-size: 16px; font-weight: 600; color: #f0f6fc; }
      .modal-close { background: none; border: none; color: #8b949e; cursor: pointer; font-size: 18px; padding: 4px; }
      .modal-close:hover { color: #f0f6fc; }
      .modal-body { padding: 20px; }
      .modal-footer { padding: 12px 20px; border-top: 1px solid #30363d; display: flex; justify-content: flex-end; gap: 8px; }
      .form-group { margin-bottom: 14px; }
      .form-label { display: block; font-size: 12px; color: #8b949e; margin-bottom: 4px; font-weight: 500; }
      .form-input { width: 100%; padding: 7px 10px; background: #0d1117; border: 1px solid #30363d; border-radius: 6px; color: #c9d1d9; font-size: 13px; font-family: inherit; }
      .form-input:focus { outline: none; border-color: #58a6ff; box-shadow: 0 0 0 2px #58a6ff30; }
      .form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
      .form-hint { font-size: 11px; color: #484f58; margin-top: 2px; }
      .form-check { display: flex; align-items: center; gap: 8px; }
      .form-check input { accent-color: #58a6ff; }

      /* Toast */
      .toast { position: fixed; bottom: 20px; right: 20px; padding: 10px 16px; border-radius: 8px; font-size: 13px; z-index: 200; animation: slideIn 0.3s; }
      .toast-success { background: #23863640; color: #3fb950; border: 1px solid #238636; }
      .toast-error { background: #f8514920; color: #f85149; border: 1px solid #f85149; }
      @keyframes slideIn { from { transform: translateY(20px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }

      /* Error banner */
      .error-banner { background: #f8514926; border: 1px solid #f85149; border-radius: 8px; padding: 10px 14px; margin-bottom: 20px; color: #f85149; font-size: 12px; }

      /* Address search */
      .address-search-box { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; margin-bottom: 20px; }
      .dir-in { color: #3fb950; font-weight: 600; }
      .dir-out { color: #f85149; font-weight: 600; }
      .dir-self { color: #d29922; font-weight: 600; }
      .addr-highlight { background: #388bfd20; border-radius: 3px; padding: 0 3px; }
    CSS
  end

  def sidebar
    mainnet_chains = @chain_configs.select { |c| c.network_type == 'mainnet' }
    testnet_chains = @chain_configs.reject { |c| c.network_type == 'mainnet' }

    chain_items = ''
    if mainnet_chains.any?
      chain_items += '<div class="nav-section">Mainnet</div>'
      chain_items += mainnet_chains.map { |c| chain_nav_item(c) }.join
    end
    if testnet_chains.any?
      chain_items += '<div class="nav-section">Testnet</div>'
      chain_items += testnet_chains.map { |c| chain_nav_item(c) }.join
    end

    <<~HTML
      <aside class="sidebar">
        <div class="sidebar-brand">
          <h1>⛓ EVM Indexer</h1>
          <p>Temporal + Rails</p>
        </div>

        <div class="nav-section">Navigation</div>
        <a class="nav-item #{@page == 'overview' || @page.blank? ? 'active' : ''}" href="/?chain_id=#{@stats[:chain_id]}">📊 Overview</a>
        <a class="nav-item #{@page == 'transfers' ? 'active' : ''}" href="/?page=transfers&chain_id=#{@stats[:chain_id]}">💸 Asset Transfers</a>
        <a class="nav-item #{@page == 'tokens' ? 'active' : ''}" href="/?page=tokens&chain_id=#{@stats[:chain_id]}">🪙 Token Contracts</a>
        <a class="nav-item #{@page == 'address' ? 'active' : ''}" href="/?page=address&chain_id=#{@stats[:chain_id]}">🔍 Address Lookup</a>
        <a class="nav-item #{@page == 'dex' ? 'active' : ''}" href="/?page=dex&chain_id=#{@stats[:chain_id]}">📈 DEX & Arbitrage</a>
        <a class="nav-item #{@page == 'webhooks' ? 'active' : ''}" href="/?page=webhooks">🔔 Webhooks</a>
        <a class="nav-item #{@page == 'chains' ? 'active' : ''}" href="/?page=chains">⚙️ Chain Config</a>

        #{chain_items}

        <div class="nav-section external-link">
          <a class="nav-item" href="http://localhost:8080" target="_blank">🔄 Temporal UI ↗</a>
        </div>
      </aside>
    HTML
  end

  def overview_page
    <<~HTML
      <div class="page-header">
        <div>
          <div class="page-title">#{h @current_chain&.name || 'Unknown'} Overview</div>
          <div class="page-subtitle">Chain ID: #{@stats[:chain_id]} · #{@current_chain&.native_currency || 'ETH'}</div>
        </div>
        <button class="btn btn-refresh" onclick="location.reload()">↻ Refresh</button>
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
          <div class="stat-label">Blocks</div>
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
          <div class="stat-label">Asset Transfers</div>
          <div class="stat-value">#{format_number(@stats[:transfers_count])}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Token Contracts</div>
          <div class="stat-value">#{format_number(@stats[:tokens_count])}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">DEX Swaps</div>
          <div class="stat-value">#{format_number(@stats[:swaps_count])}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Arb Opportunities</div>
          <div class="stat-value">#{format_number(@stats[:arb_count])}</div>
        </div>
      </div>

      #{error_banner}

      <div class="controls">
        <button class="btn btn-start" onclick="controlIndexer('start')" #{@cursor&.running? ? 'disabled' : ''}>▶ Start</button>
        <button class="btn btn-stop" onclick="controlIndexer('stop')" #{!@cursor&.running? ? 'disabled' : ''}>⏹ Stop</button>
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
    HTML
  end

  def webhooks_page
    @subscriptions = AddressSubscription.order(created_at: :desc)
    dispatcher_running = begin
      handle = TemporalClient.connection.workflow_handle('webhook-dispatcher')
      handle.describe
      true
    rescue StandardError
      false
    end
    pending_count = WebhookDelivery.pending.count
    delivered_count = WebhookDelivery.where(status: 'sent').count

    sub_rows = @subscriptions.map do |s|
      chain_name = s.chain_id ? (ChainConfig.cached_find(s.chain_id)&.name || s.chain_id.to_s) : 'All'
      types = s.transfer_types&.join(', ') || 'All'
      <<~ROW
        <tr>
          <td><span class="addr" title="#{h s.address}">#{h s.address[0..12]}...</span></td>
          <td>#{h chain_name}</td>
          <td>#{h s.direction}</td>
          <td>#{h types}</td>
          <td><span class="addr" title="#{h s.webhook_url}">#{h s.webhook_url.truncate(40)}</span></td>
          <td>#{s.label}</td>
          <td><span class="dot #{s.enabled? ? 'running' : 'stopped'}" style="display:inline-block;margin-right:4px"></span>#{s.enabled? ? 'Active' : 'Disabled'}</td>
          <td>#{s.failure_count}/#{s.max_failures}</td>
          <td>
            <button class="btn btn-sm btn-test" onclick="testWebhook(#{s.id})">🧪</button>
            <button class="btn btn-sm btn-outline" onclick="editSub(#{s.id})">✏️</button>
            <button class="btn btn-sm btn-outline" onclick="toggleSub(#{s.id}, #{!s.enabled?})">#{s.enabled? ? '⏸' : '▶'}</button>
            <button class="btn btn-sm btn-danger" onclick="deleteSub(#{s.id})">🗑</button>
          </td>
        </tr>
      ROW
    end.join

    <<~HTML
      <div class="page-header">
        <div>
          <div class="page-title">🔔 Webhook Subscriptions</div>
          <div class="page-subtitle">Monitor addresses and receive webhook notifications</div>
        </div>
        <div style="display:flex;gap:8px;align-items:center">
          <button class="btn btn-primary" onclick="showSubModal()">+ Add Subscription</button>
          <button class="btn #{dispatcher_running ? 'btn-danger' : 'btn-primary'}" onclick="toggleDispatcher(#{!dispatcher_running})" id="dispatcher-btn">
            #{dispatcher_running ? '⏹ Stop Dispatcher' : '▶ Start Dispatcher'}
          </button>
        </div>
      </div>

      <div class="stats-grid" style="margin-bottom:16px">
        <div class="stat-card">
          <div class="stat-value">#{dispatcher_running ? '🟢 Running' : '🔴 Stopped'}</div>
          <div class="stat-label">Dispatcher</div>
        </div>
        <div class="stat-card">
          <div class="stat-value">#{@subscriptions.select(&:enabled?).size}</div>
          <div class="stat-label">Active Subscriptions</div>
        </div>
        <div class="stat-card">
          <div class="stat-value">#{pending_count}</div>
          <div class="stat-label">Pending Deliveries</div>
        </div>
        <div class="stat-card">
          <div class="stat-value">#{delivered_count}</div>
          <div class="stat-label">Delivered</div>
        </div>
      </div>

      <div id="webhook-test-result" style="margin-bottom:8px;font-size:12px;display:none"></div>

      #{sub_rows.empty? ? '<div class="empty">No subscriptions yet. Add one to start monitoring addresses.</div>' : "
      <table>
        <thead><tr><th>Address</th><th>Chain</th><th>Direction</th><th>Types</th><th>Webhook URL</th><th>Label</th><th>Status</th><th>Failures</th><th>Actions</th></tr></thead>
        <tbody>#{sub_rows}</tbody>
      </table>"}

      #{webhook_modal}
      #{webhook_js}
    HTML
  end

  def webhook_modal
    chain_options = @chain_configs.map { |c| "<option value=\"#{c.chain_id}\">#{h c.name} (#{c.chain_id})</option>" }.join
    <<~HTML
      <div class="modal-overlay" id="subModal">
        <div class="modal">
          <div class="modal-header">
            <span class="modal-title" id="subModalTitle">Add Subscription</span>
            <button class="modal-close" onclick="closeSubModal()">&times;</button>
          </div>
          <div class="modal-body">
            <input type="hidden" id="subModalMode" value="add">
            <div class="form-group">
              <label class="form-label">Addresses * <span style="font-weight:normal;color:#8b949e">(one per line or comma-separated)</span></label>
              <textarea class="form-input" id="fs-address" rows="4" placeholder="0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045&#10;0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B&#10;..."></textarea>
            </div>
            <div class="form-row">
              <div class="form-group">
                <label class="form-label">Chain</label>
                <select class="form-input" id="fs-chain">
                  <option value="">All Chains</option>
                  #{chain_options}
                </select>
              </div>
              <div class="form-group">
                <label class="form-label">Direction</label>
                <select class="form-input" id="fs-direction">
                  <option value="both">Both</option>
                  <option value="incoming">Incoming</option>
                  <option value="outgoing">Outgoing</option>
                </select>
              </div>
            </div>
            <div class="form-group">
              <label class="form-label">Webhook URL *</label>
              <input class="form-input" id="fs-webhook" type="url" placeholder="https://your-server.com/webhook">
            </div>
            <div class="form-group">
              <label class="form-label">Label</label>
              <input class="form-input" id="fs-label" type="text" placeholder="My wallet monitor">
            </div>
            <div class="form-group">
              <label class="form-label">Transfer Types (leave empty for all)</label>
              <div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:4px">
                #{%w[native erc20 erc721 erc1155 internal withdrawal substrate_asset foreign_asset].map { |t|
                  "<label style='font-size:12px;display:flex;align-items:center;gap:3px'><input type='checkbox' class='fs-type-check' value='#{t}'> #{t}</label>"
                }.join}
              </div>
            </div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-outline" onclick="closeSubModal()">Cancel</button>
            <button class="btn btn-primary" onclick="saveSub()">Save</button>
          </div>
        </div>
      </div>
    HTML
  end

  def webhook_js
    <<~HTML
      <script>
      function showSubModal() {
        document.getElementById('subModalMode').value = 'add';
        document.getElementById('subModalTitle').textContent = 'Add Subscription';
        document.getElementById('fs-address').value = '';
        document.getElementById('fs-chain').value = '';
        document.getElementById('fs-direction').value = 'both';
        document.getElementById('fs-webhook').value = '';
        document.getElementById('fs-label').value = '';
        document.querySelectorAll('.fs-type-check').forEach(c => c.checked = false);
        document.getElementById('subModal').classList.add('show');
      }

      async function editSub(id) {
        try {
          const res = await fetch('/api/v1/subscriptions/' + id);
          const s = await res.json();
          document.getElementById('subModalMode').value = 'edit-' + id;
          document.getElementById('subModalTitle').textContent = 'Edit Subscription';
          document.getElementById('fs-address').value = s.address;
          document.getElementById('fs-chain').value = s.chain_id || '';
          document.getElementById('fs-direction').value = s.direction;
          document.getElementById('fs-webhook').value = s.webhook_url;
          document.getElementById('fs-label').value = s.label || '';
          document.querySelectorAll('.fs-type-check').forEach(c => {
            c.checked = s.transfer_types ? s.transfer_types.includes(c.value) : false;
          });
          document.getElementById('subModal').classList.add('show');
        } catch(e) { showToast('Error: ' + e.message, 'error'); }
      }

      function closeSubModal() { document.getElementById('subModal').classList.remove('show'); }

      async function saveSub() {
        const mode = document.getElementById('subModalMode').value;
        const raw = document.getElementById('fs-address').value;
        const addresses = raw.split(/[,\\n]+/).map(a => a.trim()).filter(a => a.length > 0);
        if (addresses.length === 0) { showToast('Enter at least one address','error'); return; }

        const base = {
          webhook_url: document.getElementById('fs-webhook').value,
          direction: document.getElementById('fs-direction').value,
          label: document.getElementById('fs-label').value || null
        };
        const chainVal = document.getElementById('fs-chain').value;
        if (chainVal) base.chain_id = parseInt(chainVal);
        const types = [];
        document.querySelectorAll('.fs-type-check:checked').forEach(c => types.push(c.value));
        if (types.length > 0) base.transfer_types = types;

        try {
          if (mode === 'add') {
            // Bulk create
            let ok = 0, errors = [];
            for (const addr of addresses) {
              const body = { ...base, address: addr };
              const res = await fetch('/api/v1/subscriptions', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body) });
              if (res.ok) { ok++; } else { const d = await res.json(); errors.push(addr.substring(0,10)+'...: '+(d.errors||[d.error]).join(', ')); }
            }
            closeSubModal();
            if (ok > 0) showToast(ok + ' subscription(s) created','success');
            if (errors.length > 0) showToast(errors.join('; '),'error');
            setTimeout(()=>location.reload(),800);
          } else {
            // Single edit
            const body = { ...base, address: addresses[0] };
            const url = '/api/v1/subscriptions/' + mode.replace('edit-','');
            const res = await fetch(url, { method:'PATCH', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body) });
            const data = await res.json();
            if (res.ok) { closeSubModal(); showToast('Saved!','success'); setTimeout(()=>location.reload(),800); }
            else { showToast((data.errors||[data.error]).join(', '),'error'); }
          }
        } catch(e) { showToast('Error: '+e.message,'error'); }
      }

      async function deleteSub(id) {
        if (!confirm('Delete this subscription?')) return;
        try {
          await fetch('/api/v1/subscriptions/'+id, {method:'DELETE'});
          showToast('Deleted','success');
          setTimeout(()=>location.reload(),500);
        } catch(e) { showToast('Error: '+e.message,'error'); }
      }

      async function toggleSub(id, enable) {
        try {
          await fetch('/api/v1/subscriptions/'+id, {
            method:'PATCH', headers:{'Content-Type':'application/json'},
            body: JSON.stringify({enabled:enable})
          });
          location.reload();
        } catch(e) { showToast('Error: '+e.message,'error'); }
      }

      async function testWebhook(id) {
        const el = document.getElementById('webhook-test-result');
        el.style.display = 'block';
        el.textContent = 'Sending test...';
        el.style.color = '#8b949e';
        try {
          const res = await fetch('/api/v1/subscriptions/'+id+'/test', {method:'POST'});
          const data = await res.json();
          if (data.status === 'ok') {
            el.innerHTML = '✅ Test webhook delivered (HTTP '+data.response_code+')';
            el.style.color = '#3fb950';
          } else {
            el.innerHTML = '❌ '+data.response_code+': '+(data.error||data.response_body||'Failed');
            el.style.color = '#f85149';
          }
        } catch(e) { el.innerHTML = '❌ '+e.message; el.style.color = '#f85149'; }
      }

      async function toggleDispatcher(start) {
        try {
          const action = start ? 'start' : 'stop';
          const res = await fetch('/api/v1/webhooks/dispatcher/'+action, {method:'POST'});
          const data = await res.json();
          showToast('Dispatcher '+(start?'started':'stopped'),'success');
          setTimeout(()=>location.reload(),1000);
        } catch(e) { showToast('Error: '+e.message,'error'); }
      }
      </script>
    HTML
  end

  def chains_page
    cards = ''
    grouped = @chain_configs.group_by(&:network_type)
    %w[mainnet testnet devnet].each do |net_type|
      chains = grouped[net_type]
      next unless chains&.any?

      cards += "<h3 style=\"margin-top:16px\">#{net_type.capitalize}</h3>"
      cards += '<div class="chain-cards">'
      cards += chains.map { |c| chain_card(c) }.join
      cards += '</div>'
    end

    <<~HTML
      <div class="page-header">
        <div>
          <div class="page-title">Chain Configuration</div>
          <div class="page-subtitle">Manage RPC endpoints and indexing settings</div>
        </div>
        <button class="btn btn-primary" onclick="showAddModal()">+ Add Chain</button>
      </div>

      #{cards}

      #{chain_modal}
    HTML
  end

  def chain_modal
    <<~HTML
      <div class="modal-overlay" id="chainModal">
        <div class="modal">
          <div class="modal-header">
            <span class="modal-title" id="modalTitle">Add Chain</span>
            <button class="modal-close" onclick="closeModal()">&times;</button>
          </div>
          <div class="modal-body">
            <input type="hidden" id="modalMode" value="add">
            <div class="form-row">
              <div class="form-group">
                <label class="form-label">Chain ID *</label>
                <input class="form-input" id="f-chain-id" type="number" placeholder="56">
              </div>
              <div class="form-group">
                <label class="form-label">Name *</label>
                <input class="form-input" id="f-name" type="text" placeholder="BSC">
              </div>
            </div>
            <div class="form-row">
              <div class="form-group">
                <label class="form-label">Chain Type *</label>
                <select class="form-input" id="f-chain-type" onchange="onChainTypeChange()">
                  <option value="evm">EVM</option>
                  <option value="utxo">UTXO (Bitcoin)</option>
                  <option value="substrate">Substrate</option>
                </select>
              </div>
              <div class="form-group">
                <label class="form-label">Network Type</label>
                <select class="form-input" id="f-network-type">
                  <option value="mainnet">Mainnet</option>
                  <option value="testnet">Testnet</option>
                  <option value="devnet">Devnet</option>
                </select>
              </div>
            </div>
            <div class="form-group">
              <label class="form-label">RPC URL *</label>
              <input class="form-input" id="f-rpc-url" type="url" placeholder="https://bsc-dataseed.binance.org">
              <div class="form-hint">HTTPS endpoint for JSON-RPC. Alchemy/Infura URLs with API keys supported.</div>
            </div>
            <div class="form-group" id="sidecar-url-group" style="display:none">
              <label class="form-label">Sidecar URL (Substrate only)</label>
              <input class="form-input" id="f-sidecar-url" type="url" placeholder="https://polkadot-asset-hub-public-sidecar.parity-chains.parity.io">
              <div class="form-hint">Substrate Sidecar REST API endpoint for decoded extrinsics/events.</div>
            </div>
            <div class="form-group">
              <label class="form-label">Additional RPC Endpoints</label>
              <div id="rpc-endpoints-list"></div>
              <button class="btn btn-sm btn-outline" type="button" onclick="addRpcEndpoint()" style="margin-top:6px">+ Add Endpoint</button>
              <div class="form-hint">Priority: lower number = higher priority. Label is optional.</div>
            </div>
            <div class="form-group">
              <label class="form-label">Explorer URL</label>
              <input class="form-input" id="f-explorer" type="url" placeholder="https://etherscan.io">
            </div>
            <div class="form-row">
              <div class="form-group">
                <label class="form-label">Native Currency</label>
                <input class="form-input" id="f-currency" type="text" value="ETH" placeholder="ETH">
              </div>
              <div class="form-group">
                <label class="form-label">Block Time (ms)</label>
                <input class="form-input" id="f-block-time" type="number" value="12000">
              </div>
            </div>
            <div class="form-row">
              <div class="form-group">
                <label class="form-label">Poll Interval (seconds)</label>
                <input class="form-input" id="f-poll-interval" type="number" value="2">
              </div>
              <div class="form-group">
                <label class="form-label">Blocks per Batch</label>
                <input class="form-input" id="f-batch-size" type="number" value="10">
              </div>
            </div>
            <div class="form-row">
              <div class="form-group">
                <label class="form-label">Block Tag (Finality)</label>
                <select class="form-input" id="f-block-tag">
                  <option value="finalized">Finalized</option>
                  <option value="safe">Safe</option>
                  <option value="latest">Latest</option>
                </select>
                <div class="form-hint">EVM: finalized/safe/latest. UTXO/Substrate: finalized recommended.</div>
              </div>
              <div class="form-group">
                <label class="form-label">Confirmation Blocks</label>
                <input class="form-input" id="f-confirm-blocks" type="number" value="0">
                <div class="form-hint">Fallback for tag=latest or UTXO (default: 6 for Bitcoin)</div>
              </div>
            </div>
            <div class="form-row">
              <div class="form-group">
                <div class="form-check">
                  <input type="checkbox" id="f-enabled" checked>
                  <label class="form-label" for="f-enabled" style="margin:0">Enabled</label>
                </div>
              </div>
              <div class="form-group" id="supports-trace-group">
                <div class="form-check">
                  <input type="checkbox" id="f-supports-trace">
                  <label class="form-label" for="f-supports-trace" style="margin:0">Supports Trace (EVM only)</label>
                </div>
              </div>
            </div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-outline" onclick="closeModal()">Cancel</button>
            <button class="btn btn-primary" onclick="saveChain()">Save</button>
          </div>
        </div>
      </div>
    HTML
  end

  def javascript
    <<~JS
      const chainId = #{@stats[:chain_id]};
      const chainExplorers = {#{@chain_configs.map { |c| c.explorer_url.present? ? "#{c.chain_id}:'#{c.explorer_url.chomp('/')}'" : nil }.compact.join(',')}};
      function getExplorer(cid) { return chainExplorers[cid || chainId] || null; }

      // Convert UTC timestamps to local time
      function initLocalTimes() {
        document.querySelectorAll('.local-time[data-ts]').forEach(el => {
          const ts = parseInt(el.dataset.ts, 10);
          if (!isNaN(ts)) {
            const d = new Date(ts * 1000);
            el.textContent = d.toLocaleString(undefined, {year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit'});
            el.title = d.toISOString();
          }
        });
      }
      document.addEventListener('DOMContentLoaded', initLocalTimes);

      // Indexer controls
      async function controlIndexer(action) {
        const msg = document.getElementById('control-msg');
        msg.textContent = 'Processing...';
        try {
          const res = await fetch('/api/v1/indexer/' + action + '?chain_id=' + chainId, { method: 'POST' });
          const data = await res.json();
          msg.textContent = data.status || data.error || JSON.stringify(data);
          setTimeout(() => location.reload(), 1500);
        } catch(e) { msg.textContent = 'Error: ' + e.message; }
      }

      // Chain test
      async function testChain(id) {
        const el = document.getElementById('test-result-' + id);
        el.style.display = 'block';
        el.textContent = 'Testing...';
        el.style.color = '#8b949e';
        try {
          const res = await fetch('/api/v1/chains/' + id + '/test', { method: 'POST' });
          const data = await res.json();
          if (data.status === 'ok') {
            el.innerHTML = '✅ Connected — Block #' + data.latest_block.toLocaleString() + ' (' + data.latency_ms + 'ms)';
            el.style.color = '#3fb950';
          } else {
            el.innerHTML = '❌ ' + (data.error || 'Unknown error');
            el.style.color = '#f85149';
          }
        } catch(e) {
          el.innerHTML = '❌ ' + e.message;
          el.style.color = '#f85149';
        }
      }

      // Toggle enable/disable
      async function toggleChain(id, enable) {
        try {
          await fetch('/api/v1/chains/' + id, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ enabled: enable })
          });
          location.reload();
        } catch(e) { showToast('Error: ' + e.message, 'error'); }
      }

      // Modal
      let rpcEndpointIdx = 0;
      function addRpcEndpoint(url='', label='', priority='') {
        const list = document.getElementById('rpc-endpoints-list');
        const idx = rpcEndpointIdx++;
        const row = document.createElement('div');
        row.className = 'form-row';
        row.style.marginBottom = '6px';
        row.id = 'rpc-ep-' + idx;
        row.innerHTML = '<div class="form-group" style="margin:0;grid-column:span 2"><div style="display:flex;gap:6px"><input class="form-input rpc-ep-url" type="url" placeholder="https://..." value="'+url+'" style="flex:3"><input class="form-input rpc-ep-label" type="text" placeholder="Label" value="'+label+'" style="flex:1"><input class="form-input rpc-ep-priority" type="number" placeholder="P" value="'+priority+'" style="flex:0.5;min-width:50px"><button class="btn btn-sm btn-danger" type="button" onclick="document.getElementById(\\'rpc-ep-'+idx+'\\').remove()">✕</button></div></div>';
        list.appendChild(row);
      }

      function getRpcEndpoints() {
        const eps = [];
        document.querySelectorAll('#rpc-endpoints-list .form-row').forEach(row => {
          const url = row.querySelector('.rpc-ep-url')?.value;
          const label = row.querySelector('.rpc-ep-label')?.value;
          const priority = parseInt(row.querySelector('.rpc-ep-priority')?.value) || 99;
          if (url) eps.push({ url, label: label || '', priority });
        });
        return eps;
      }

      function onChainTypeChange() {
        const ct = document.getElementById('f-chain-type').value;
        document.getElementById('sidecar-url-group').style.display = ct === 'substrate' ? '' : 'none';
        document.getElementById('supports-trace-group').style.display = ct === 'evm' ? '' : 'none';
      }

      function showAddModal() {
        document.getElementById('modalMode').value = 'add';
        document.getElementById('modalTitle').textContent = 'Add Chain';
        document.getElementById('f-chain-id').value = '';
        document.getElementById('f-chain-id').disabled = false;
        document.getElementById('f-chain-type').value = 'evm';
        document.getElementById('f-name').value = '';
        document.getElementById('f-network-type').value = 'mainnet';
        document.getElementById('f-rpc-url').value = '';
        document.getElementById('f-sidecar-url').value = '';
        document.getElementById('rpc-endpoints-list').innerHTML = '';
        rpcEndpointIdx = 0;
        document.getElementById('f-explorer').value = '';
        document.getElementById('f-currency').value = 'ETH';
        document.getElementById('f-block-time').value = '12000';
        document.getElementById('f-poll-interval').value = '2';
        document.getElementById('f-batch-size').value = '10';
        document.getElementById('f-block-tag').value = 'finalized';
        document.getElementById('f-confirm-blocks').value = '0';
        document.getElementById('f-enabled').checked = true;
        document.getElementById('f-supports-trace').checked = false;
        onChainTypeChange();
        document.getElementById('chainModal').classList.add('show');
      }

      async function editChain(id) {
        try {
          const res = await fetch('/api/v1/chains/' + id);
          const c = await res.json();
          document.getElementById('modalMode').value = 'edit-' + id;
          document.getElementById('modalTitle').textContent = 'Edit ' + c.name;
          document.getElementById('f-chain-id').value = c.chain_id;
          document.getElementById('f-chain-id').disabled = true;
          document.getElementById('f-chain-type').value = c.chain_type || 'evm';
          document.getElementById('f-name').value = c.name;
          document.getElementById('f-network-type').value = c.network_type || 'mainnet';
          document.getElementById('f-rpc-url').value = '';
          document.getElementById('f-rpc-url').placeholder = c.rpc_url + ' (leave blank to keep)';
          document.getElementById('f-sidecar-url').value = c.sidecar_url || '';
          document.getElementById('rpc-endpoints-list').innerHTML = '';
          rpcEndpointIdx = 0;
          (c.rpc_endpoints || []).forEach(ep => addRpcEndpoint(ep.url || '', ep.label || '', ep.priority || ''));
          document.getElementById('f-explorer').value = c.explorer_url || '';
          document.getElementById('f-currency').value = c.native_currency;
          document.getElementById('f-block-time').value = c.block_time_ms;
          document.getElementById('f-poll-interval').value = c.poll_interval_seconds;
          document.getElementById('f-batch-size').value = c.blocks_per_batch;
          document.getElementById('f-block-tag').value = c.block_tag || 'finalized';
          document.getElementById('f-confirm-blocks').value = c.confirmation_blocks || 0;
          document.getElementById('f-enabled').checked = c.enabled;
          document.getElementById('f-supports-trace').checked = c.supports_trace || false;
          onChainTypeChange();
          document.getElementById('chainModal').classList.add('show');
        } catch(e) { showToast('Error loading chain: ' + e.message, 'error'); }
      }

      function closeModal() {
        document.getElementById('chainModal').classList.remove('show');
      }

      async function saveChain() {
        const mode = document.getElementById('modalMode').value;
        const body = {};
        if (mode === 'add') body.chain_id = parseInt(document.getElementById('f-chain-id').value);
        body.chain_type = document.getElementById('f-chain-type').value;
        body.name = document.getElementById('f-name').value;
        body.network_type = document.getElementById('f-network-type').value;
        const rpc = document.getElementById('f-rpc-url').value;
        if (rpc) body.rpc_url = rpc;
        const sidecar = document.getElementById('f-sidecar-url').value;
        if (sidecar) body.sidecar_url = sidecar;
        const endpoints = getRpcEndpoints();
        if (endpoints.length > 0) body.rpc_endpoints = endpoints;
        body.explorer_url = document.getElementById('f-explorer').value || null;
        body.native_currency = document.getElementById('f-currency').value;
        body.block_time_ms = parseInt(document.getElementById('f-block-time').value);
        body.poll_interval_seconds = parseInt(document.getElementById('f-poll-interval').value);
        body.blocks_per_batch = parseInt(document.getElementById('f-batch-size').value);
        body.block_tag = document.getElementById('f-block-tag').value;
        body.confirmation_blocks = parseInt(document.getElementById('f-confirm-blocks').value) || 0;
        body.enabled = document.getElementById('f-enabled').checked;
        body.supports_trace = document.getElementById('f-supports-trace').checked;

        try {
          let url, method;
          if (mode === 'add') {
            url = '/api/v1/chains';
            method = 'POST';
          } else {
            const editId = mode.replace('edit-', '');
            url = '/api/v1/chains/' + editId;
            method = 'PATCH';
          }
          const res = await fetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
          const data = await res.json();
          if (res.ok) {
            closeModal();
            showToast('Chain saved!', 'success');
            setTimeout(() => location.reload(), 800);
          } else {
            showToast((data.errors || [data.error]).join(', '), 'error');
          }
        } catch(e) { showToast('Error: ' + e.message, 'error'); }
      }

      function showToast(msg, type) {
        const t = document.createElement('div');
        t.className = 'toast toast-' + type;
        t.textContent = msg;
        document.body.appendChild(t);
        setTimeout(() => t.remove(), 3000);
      }

      // Auto-refresh on overview (not chains/address page)
      if (!window.location.search.includes('page=chains') && !window.location.search.includes('page=address') && !window.location.search.includes('page=webhooks')) {
        setTimeout(() => location.reload(), 10000);
      }

      // Address lookup
      let addrOffset = 0;
      let addrCurrentData = null;

      async function searchAddresses(offset = 0) {
        const raw = document.getElementById('addr-input').value;
        const addrs = raw.split(/[,\\n]+/).map(a => a.trim().toLowerCase()).filter(a => /^0x[0-9a-f]{40}$/.test(a));
        if (addrs.length === 0) { showToast('Enter at least one valid address', 'error'); return; }

        const chain = document.getElementById('addr-chain').value;
        const type = document.getElementById('addr-type').value;
        const dir = document.getElementById('addr-direction').value;
        const limit = document.getElementById('addr-limit').value;
        addrOffset = offset;

        const status = document.getElementById('addr-status');
        status.style.display = 'block';
        status.textContent = 'Searching...';
        document.getElementById('addr-search-btn').disabled = true;

        let url = '/api/v1/address_transfers?addresses=' + addrs.join(',') + '&chain_id=' + chain + '&limit=' + limit + '&offset=' + offset;
        if (type) url += '&type=' + type;

        try {
          const res = await fetch(url);
          const data = await res.json();
          if (!res.ok) { status.textContent = '❌ ' + (data.error || 'Error'); return; }

          addrCurrentData = data;
          const transfers = data.transfers || [];

          // Filter by direction client-side
          const filtered = dir ? transfers.filter(t => t.direction === dir) : transfers;

          status.textContent = transfers.length + ' results' + (dir ? ' (' + filtered.length + ' after filter)' : '') + ' · offset ' + offset;

          // Summary stats
          renderAddrSummary(transfers, addrs);

          // Table
          renderAddrTable(filtered, addrs, chain);

          // Pagination
          const pag = document.getElementById('addr-pagination');
          pag.style.display = 'flex';
          document.getElementById('addr-prev').disabled = offset === 0;
          document.getElementById('addr-next').disabled = transfers.length < parseInt(limit);
          document.getElementById('addr-page-info').textContent = 'Showing ' + (offset + 1) + '-' + (offset + transfers.length);

        } catch(e) {
          status.textContent = '❌ ' + e.message;
        } finally {
          document.getElementById('addr-search-btn').disabled = false;
        }
      }

      function addrPagePrev() {
        const limit = parseInt(document.getElementById('addr-limit').value);
        searchAddresses(Math.max(0, addrOffset - limit));
      }
      function addrPageNext() {
        const limit = parseInt(document.getElementById('addr-limit').value);
        searchAddresses(addrOffset + limit);
      }

      function renderAddrSummary(transfers, addrs) {
        const addrSet = new Set(addrs);
        let inCount = 0, outCount = 0, selfCount = 0;
        let inNative = 0n, outNative = 0n;
        transfers.forEach(t => {
          const isEth = (t.transfer_type === 'native' || t.transfer_type === 'withdrawal' || t.transfer_type === 'internal');
          if (t.direction === 'in') { inCount++; if (isEth) inNative += BigInt(t.amount); }
          else if (t.direction === 'out') { outCount++; if (isEth) outNative += BigInt(t.amount); }
          else { selfCount++; }
        });

        const summary = document.getElementById('addr-summary');
        summary.style.display = 'block';
        document.getElementById('addr-stats').innerHTML =
          '<div class="stat-card"><div class="stat-label">↓ Incoming</div><div class="stat-value" style="color:#3fb950">' + inCount + '</div></div>' +
          '<div class="stat-card"><div class="stat-label">↑ Outgoing</div><div class="stat-value" style="color:#f85149">' + outCount + '</div></div>' +
          '<div class="stat-card"><div class="stat-label">↔ Self</div><div class="stat-value" style="color:#d29922">' + selfCount + '</div></div>' +
          '<div class="stat-card"><div class="stat-label">Total</div><div class="stat-value">' + transfers.length + '</div></div>';
      }

      function renderAddrTable(transfers, addrs, chainId) {
        const results = document.getElementById('addr-results');
        if (transfers.length === 0) {
          results.innerHTML = '<div class="empty">No transfers found for these addresses</div>';
          return;
        }

        const addrSet = new Set(addrs);
        const explorer = getExplorer(chainId);

        let rows = '';
        transfers.forEach(t => {
          const dirClass = t.direction === 'in' ? 'dir-in' : t.direction === 'out' ? 'dir-out' : 'dir-self';
          const dirLabel = t.direction === 'in' ? '↓ IN' : t.direction === 'out' ? '↑ OUT' : '↔ SELF';
          const typeBadge = {native:'<span style="color:#3fb950">ETH</span>',erc20:'<span style="color:#58a6ff">ERC20</span>',erc721:'<span style="color:#d2a8ff">NFT</span>',erc1155:'<span style="color:#d29922">1155</span>',internal:'<span style="color:#f79000">INT</span>',withdrawal:'<span style="color:#da70d6">WD</span>'}[t.transfer_type] || t.transfer_type;

          const txLink = explorer ? '<a href="' + explorer + '/tx/' + t.tx_hash + '" target="_blank" class="hash">' + t.tx_hash.slice(0,10) + '...' + '</a>' : '<span class="hash">' + t.tx_hash.slice(0,10) + '...</span>';

          const fmtAddr = (addr) => {
            if (!addr) return '—';
            const short = addr.slice(0,8) + '...' + addr.slice(-4);
            const cls = addrSet.has(addr) ? 'addr addr-highlight' : 'addr';
            return explorer ? '<a href="' + explorer + '/address/' + addr + '" target="_blank" class="' + cls + '" title="' + addr + '">' + short + '</a>' : '<span class="' + cls + '" title="' + addr + '">' + short + '</span>';
          };

          const amount = t.transfer_type === 'erc721' ? 'NFT #' + (t.token_id || '?') : (t.amount_display || t.amount);
          const symbol = t.token_symbol || '';

          rows += '<tr><td>' + txLink + '</td><td class="num">' + t.block_number + '</td><td class="' + dirClass + '">' + dirLabel + '</td><td>' + typeBadge + '</td><td>' + fmtAddr(t.from_address) + '</td><td>' + fmtAddr(t.to_address) + '</td><td class="num" title="' + t.amount + '">' + amount + '</td><td>' + symbol + '</td></tr>';
        });

        results.innerHTML = '<table><thead><tr><th>Tx</th><th>Block</th><th>Dir</th><th>Type</th><th>From</th><th>To</th><th>Amount</th><th>Token</th></tr></thead><tbody>' + rows + '</tbody></table>';
      }

      // Auto-search if addresses in URL
      if (window.location.search.includes('page=address') && document.getElementById('addr-input')?.value?.trim()) {
        searchAddresses();
      }
    JS
  end

  def chain_card(c)
    cursor = IndexerCursor.find_by(chain_id: c.chain_id)
    status = cursor&.status || 'not_initialized'
    badge_class = case c.network_type
                  when 'mainnet' then 'badge-mainnet'
                  when 'testnet' then 'badge-testnet'
                  else 'badge-devnet'
                  end
    <<~CARD
      <div class="chain-card #{c.enabled? ? '' : 'disabled'}" id="chain-card-#{c.chain_id}">
        <div class="chain-card-header">
          <div>
            <div class="chain-card-title">#{h c.name}</div>
            <div class="chain-card-id">Chain ID: #{c.chain_id}</div>
          </div>
          <div style="display:flex;gap:6px">
            <span class="chain-card-badge #{badge_class}">#{c.network_type}</span>
            <span class="chain-card-badge #{c.enabled? ? 'badge-enabled' : 'badge-disabled'}">#{c.enabled? ? 'Enabled' : 'Disabled'}</span>
          </div>
        </div>
        <div class="chain-card-body">
          <div class="chain-card-row"><span class="chain-card-label">Type</span><span class="chain-card-value"><span class="chain-card-badge" style="font-size:10px;padding:1px 6px">#{(c.chain_type || 'evm').upcase}</span>#{c.chain_type == 'evm' && c.supports_trace ? ' <span style="color:#3fb950;font-size:10px">🔍 Trace</span>' : ''}</span></div>
          <div class="chain-card-row"><span class="chain-card-label">RPC</span><span class="chain-card-value" title="#{h c.rpc_url}">#{h c.rpc_url}</span></div>
          #{c.sidecar_url.present? ? "<div class=\"chain-card-row\"><span class=\"chain-card-label\">Sidecar</span><span class=\"chain-card-value\">#{h c.sidecar_url}</span></div>" : ''}
          #{(c.rpc_endpoints || []).map { |ep| "<div class=\"chain-card-row\"><span class=\"chain-card-label\">#{h(ep['label'] || 'Endpoint')} (P#{ep['priority'] || '?'})</span><span class=\"chain-card-value\">#{h ep['url']}</span></div>" }.join}
          <div class="chain-card-row"><span class="chain-card-label">Currency</span><span class="chain-card-value">#{h c.native_currency}</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Block Time</span><span class="chain-card-value">#{c.block_time_ms}ms</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Poll Interval</span><span class="chain-card-value">#{c.poll_interval_seconds}s</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Batch Size</span><span class="chain-card-value">#{c.blocks_per_batch}</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Finality</span><span class="chain-card-value">#{c.block_tag}#{c.confirmation_blocks.to_i > 0 ? " (#{c.confirmation_blocks} confirms)" : ''}</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Status</span><span class="chain-card-value"><span class="dot #{status}" style="display:inline-block;margin-right:4px"></span>#{status}</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Last Block</span><span class="chain-card-value">#{format_number(cursor&.last_indexed_block || 0)}</span></div>
        </div>
        <div class="chain-card-actions">
          <button class="btn btn-sm btn-test" onclick="testChain(#{c.chain_id})">🔌 Test RPC</button>
          <button class="btn btn-sm btn-outline" onclick="editChain(#{c.chain_id})">✏️ Edit</button>
          <button class="btn btn-sm btn-outline" onclick="toggleChain(#{c.chain_id}, #{!c.enabled?})">#{c.enabled? ? '⏸ Disable' : '▶ Enable'}</button>
        </div>
        <div id="test-result-#{c.chain_id}" style="margin-top:8px;font-size:11px;color:#8b949e;display:none"></div>
      </div>
    CARD
  end

  def chain_nav_item(c)
    cursor = IndexerCursor.find_by(chain_id: c.chain_id)
    status = cursor&.status || 'not_initialized'
    active = c.chain_id == @stats[:chain_id] && @page != 'chains' ? 'active' : ''
    <<~ITEM
      <a class="nav-chain #{active}" href="/?chain_id=#{c.chain_id}">
        <span class="nav-chain-name"><span class="dot #{status}"></span> #{h c.name}</span>
        <span style="color:#484f58;font-size:10px">#{c.chain_id}</span>
      </a>
    ITEM
  end

  def error_banner
    return '' unless @cursor&.error_message.present?

    %(<div class="error-banner">⚠️ #{h @cursor.error_message}</div>)
  end

  def blocks_table
    return %(<div class="empty">No blocks indexed yet</div>) if @blocks.empty?

    rows = @blocks.map do |b|
      "<tr><td>#{link_block(b.number)}</td><td>#{link_block_hash(b.block_hash,
                                                                 b.number)}</td><td><span class=\"local-time\" data-ts=\"#{b.timestamp}\"></span></td><td>#{link_address(b.miner)}</td><td class=\"num\">#{b.transaction_count}</td><td class=\"num\">#{format_number(b.gas_used)}</td></tr>"
    end.join
    "<table><thead><tr><th>Block</th><th>Hash</th><th>Timestamp</th><th>Miner</th><th>Txns</th><th>Gas</th></tr></thead><tbody>#{rows}</tbody></table>"
  end

  def transactions_table
    return %(<div class="empty">No transactions indexed yet</div>) if @transactions.empty?

    rows = @transactions.map do |tx|
      "<tr><td>#{link_tx(tx.tx_hash)}</td><td>#{link_block(tx.block_number)}</td><td>#{link_address(tx.from_address)}</td><td>#{link_address(tx.to_address)}</td><td class=\"num\">#{format_wei(tx.value)}</td><td>#{tx.status == 1 ? '✅' : '❌'}</td></tr>"
    end.join
    "<table><thead><tr><th>Tx Hash</th><th>Block</th><th>From</th><th>To</th><th>Value</th><th>St</th></tr></thead><tbody>#{rows}</tbody></table>"
  end

  def logs_table
    return %(<div class="empty">No event logs indexed yet</div>) if @logs.empty?

    rows = @logs.map do |log|
      "<tr><td>#{link_block(log.block_number)}</td><td>#{link_tx(log.tx_hash)}</td><td>#{link_address(log.address)}</td><td class=\"hash\" title=\"#{log.topic0}\">#{truncate_hash(log.topic0)}</td><td class=\"num\">#{log.log_index}</td></tr>"
    end.join
    "<table><thead><tr><th>Block</th><th>Tx Hash</th><th>Contract</th><th>Event</th><th>Idx</th></tr></thead><tbody>#{rows}</tbody></table>"
  end

  def truncate_hash(hash)
    return '—' if hash.blank?

    "#{hash[0..7]}...#{hash[-6..]}"
  end

  def link_block(number)
    return '—' if number.nil?

    if @explorer
      "<a href=\"#{@explorer}/block/#{number}\" target=\"_blank\" class=\"num\">#{number}</a>"
    else
      "<span class=\"num\">#{number}</span>"
    end
  end

  def link_tx(hash)
    return '—' if hash.blank?

    display = truncate_hash(hash)
    if @explorer
      "<a href=\"#{@explorer}/tx/#{hash}\" target=\"_blank\" class=\"hash\" title=\"#{hash}\">#{display}</a>"
    else
      "<span class=\"hash\" title=\"#{hash}\">#{display}</span>"
    end
  end

  def link_address(addr)
    return '—' if addr.blank?

    display = truncate_hash(addr)
    if @explorer
      "<a href=\"#{@explorer}/address/#{addr}\" target=\"_blank\" class=\"addr\" title=\"#{addr}\">#{display}</a>"
    else
      "<span class=\"addr\" title=\"#{addr}\">#{display}</span>"
    end
  end

  def link_block_hash(hash, number)
    return '—' if hash.blank?

    display = truncate_hash(hash)
    if @explorer
      "<a href=\"#{@explorer}/block/#{number}\" target=\"_blank\" class=\"hash\" title=\"#{hash}\">#{display}</a>"
    else
      "<span class=\"hash\" title=\"#{hash}\">#{display}</span>"
    end
  end

  def format_number(num)
    return '0' if num.nil? || num.zero?

    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def format_wei(wei)
    return '0' if wei.nil? || wei.zero?

    eth = wei.to_f / 1e18
    eth < 0.0001 ? '< 0.0001' : '%.4f' % eth
  end

  def transfers_page
    <<~HTML
      <div class="page-header">
        <div>
          <div class="page-title">Asset Transfers</div>
          <div class="page-subtitle">Chain ID: #{@stats[:chain_id]} · #{format_number(@stats[:transfers_count])} total transfers</div>
        </div>
        <button class="btn btn-refresh" onclick="location.reload()">↻ Refresh</button>
      </div>

      <div class="section">
        <h3>Recent Asset Transfers</h3>
        #{transfers_table}
      </div>
    HTML
  end

  def tokens_page
    <<~HTML
      <div class="page-header">
        <div>
          <div class="page-title">Token Contracts</div>
          <div class="page-subtitle">Chain ID: #{@stats[:chain_id]} · #{format_number(@stats[:tokens_count])} token contracts</div>
        </div>
        <button class="btn btn-refresh" onclick="location.reload()">↻ Refresh</button>
      </div>

      <div class="section">
        <h3>Token Contracts</h3>
        #{tokens_table}
      </div>
    HTML
  end

  def transfers_table
    return %(<div class="empty">No asset transfers indexed yet</div>) if @asset_transfers.empty?

    rows = @asset_transfers.map do |transfer|
      token_info = case transfer.transfer_type
                   when 'native', 'internal', 'withdrawal'
                     "<span class=\"num\">#{transfer.token_symbol}</span>"
                   else
                     token_name = transfer.token_contract&.display_name || 'Unknown'
                     if @explorer && transfer.token_address
                       "<a href=\"#{@explorer}/token/#{transfer.token_address}\" target=\"_blank\" class=\"addr\" title=\"#{transfer.token_address}\">#{h token_name}</a>"
                     else
                       "<span class=\"addr\" title=\"#{transfer.token_address}\">#{h token_name}</span>"
                     end
                   end

      amount_display = transfer.nft? ? "NFT ##{transfer.token_id}" : transfer.formatted_amount.to_s
      type_badge = case transfer.transfer_type
                   when 'native' then '<span style="color:#3fb950">ETH</span>'
                   when 'erc20' then '<span style="color:#58a6ff">ERC20</span>'
                   when 'erc721' then '<span style="color:#d2a8ff">ERC721</span>'
                   when 'erc1155' then '<span style="color:#d29922">ERC1155</span>'
                   when 'internal' then '<span style="color:#f79000">Internal</span>'
                   when 'withdrawal' then '<span style="color:#da70d6">Withdrawal</span>'
                   else transfer.transfer_type.upcase
                   end

      tx_display = transfer.tx_hash&.start_with?('withdrawal-') ? "<span class=\"hash\">#{h transfer.tx_hash[0..20]}...</span>" : link_tx(transfer.tx_hash)
      "<tr><td>#{tx_display}</td><td>#{link_block(transfer.block_number)}</td><td>#{type_badge}</td><td>#{token_info}</td><td>#{link_address(transfer.from_address)}</td><td>#{link_address(transfer.to_address)}</td><td class=\"num\">#{h amount_display}</td></tr>"
    end.join
    "<table><thead><tr><th>Tx Hash</th><th>Block</th><th>Type</th><th>Token</th><th>From</th><th>To</th><th>Amount</th></tr></thead><tbody>#{rows}</tbody></table>"
  end

  def tokens_table
    return %(<div class="empty">No token contracts discovered yet</div>) if @token_contracts.empty?

    rows = @token_contracts.map do |token|
      name_display = if token.name.present? && token.symbol.present?
                       "#{h token.name} (#{h token.symbol})"
                     elsif token.symbol.present?
                       h token.symbol
                     elsif token.name.present?
                       h token.name
                     else
                       'Unknown'
                     end

      standard_badge = case token.standard
                       when 'erc20' then '<span style="color:#58a6ff">ERC-20</span>'
                       when 'erc721' then '<span style="color:#d2a8ff">ERC-721</span>'
                       when 'erc1155' then '<span style="color:#d29922">ERC-1155</span>'
                       else '<span style="color:#8b949e">Unknown</span>'
                       end

      decimals_display = token.decimals ? token.decimals.to_s : '—'
      transfer_count = token.asset_transfers.count

      "<tr><td>#{link_address(token.address)}</td><td>#{name_display}</td><td>#{standard_badge}</td><td class=\"num\">#{decimals_display}</td><td class=\"num\">#{format_number(transfer_count)}</td></tr>"
    end.join
    "<table><thead><tr><th>Contract Address</th><th>Name</th><th>Standard</th><th>Decimals</th><th>Transfers</th></tr></thead><tbody>#{rows}</tbody></table>"
  end

  def dex_page
    arb_rows = @arb_opportunities.map do |a|
      pool_buy = DexPool.find_by(chain_id: a.chain_id, pool_address: a.pool_buy)
      pool_sell = DexPool.find_by(chain_id: a.chain_id, pool_address: a.pool_sell)
      token0 = pool_buy&.token0_symbol || pool_buy&.token0_address&.then { |addr| truncate_hash(addr) } || '?'
      token1 = pool_buy&.token1_symbol || pool_buy&.token1_address&.then { |addr| truncate_hash(addr) } || '?'

      spread_color = if a.spread_bps.to_f >= 100
                       '#3fb950'
                     elsif a.spread_bps.to_f >= 30
                       '#d29922'
                     else
                       '#8b949e'
                     end

      "<tr><td>#{link_block(a.block_number)}</td>" \
      "<td><span style=\"color:#{spread_color};font-weight:600\">#{a.spread_bps.to_f.round(1)} bps</span></td>" \
      "<td>#{h token0}/#{h token1}</td>" \
      "<td>#{h a.dex_buy || '?'} #{a.tx_hash_buy ? link_tx(a.tx_hash_buy) : ''}</td>" \
      "<td>#{h a.dex_sell || '?'} #{a.tx_hash_sell ? link_tx(a.tx_hash_sell) : ''}</td>" \
      "<td class=\"num\">#{a.price_buy&.round(4)}</td>" \
      "<td class=\"num\">#{a.price_sell&.round(4)}</td>" \
      "<td>#{h a.arb_type}</td></tr>"
    end.join

    swap_rows = @dex_swaps.map do |s|
      pool = DexPool.cached_find(s.chain_id, s.pool_address)
      t_in = resolve_token_symbol(pool, s.token_in)
      t_out = resolve_token_symbol(pool, s.token_out)

      "<tr><td>#{link_block(s.block_number)}</td>" \
      "<td>#{link_tx(s.tx_hash)}</td>" \
      "<td>#{h s.dex_name || '?'}</td>" \
      "<td>#{link_address(s.pool_address)}</td>" \
      "<td><span style=\"color:#f85149\">#{h t_in}</span> → <span style=\"color:#3fb950\">#{h t_out}</span></td>" \
      "<td class=\"num\" title=\"#{s.amount_in}\">#{format_swap_amount(s.amount_in)}</td>" \
      "<td class=\"num\" title=\"#{s.amount_out}\">#{format_swap_amount(s.amount_out)}</td></tr>"
    end.join

    <<~HTML
      <div class="page-header">
        <div>
          <div class="page-title">📈 DEX Swaps & Arbitrage</div>
          <div class="page-subtitle">Chain ID: #{@stats[:chain_id]} · #{format_number(@stats[:pools_count])} pools · #{format_number(@stats[:swaps_count])} swaps · #{format_number(@stats[:arb_count])} opportunities</div>
        </div>
        <button class="btn btn-refresh" onclick="location.reload()">↻ Refresh</button>
      </div>

      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-label">DEX Pools</div>
          <div class="stat-value">#{format_number(@stats[:pools_count])}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Total Swaps</div>
          <div class="stat-value">#{format_number(@stats[:swaps_count])}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Arb Opportunities</div>
          <div class="stat-value">#{format_number(@stats[:arb_count])}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Avg Spread (last 20)</div>
          <div class="stat-value">#{@arb_opportunities.any? ? ('%.1f' % (@arb_opportunities.map { |a| a.spread_bps.to_f }.sum / @arb_opportunities.size)) + ' bps' : '—'}</div>
        </div>
      </div>

      <div class="section">
        <h3>🎯 Recent Arbitrage Opportunities</h3>
        #{arb_rows.empty? ? '<div class="empty">No arbitrage opportunities detected yet</div>' : "
        <table>
          <thead><tr><th>Block</th><th>Spread</th><th>Pair</th><th>Buy @</th><th>Sell @</th><th>Price Buy</th><th>Price Sell</th><th>Type</th></tr></thead>
          <tbody>#{arb_rows}</tbody>
        </table>"}
      </div>

      <div class="section">
        <h3>🔄 Recent DEX Swaps</h3>
        #{swap_rows.empty? ? '<div class="empty">No DEX swaps detected yet</div>' : "
        <table>
          <thead><tr><th>Block</th><th>Tx</th><th>DEX</th><th>Pool</th><th>Swap</th><th>Amount In</th><th>Amount Out</th></tr></thead>
          <tbody>#{swap_rows}</tbody>
        </table>"}
      </div>
    HTML
  end

  def resolve_token_symbol(pool, token_address)
    return token_address&.then { |a| truncate_hash(a) } || '?' unless pool
    if token_address == pool.token0_address
      pool.token0_symbol || truncate_hash(token_address)
    elsif token_address == pool.token1_address
      pool.token1_symbol || truncate_hash(token_address)
    else
      token_address&.then { |a| truncate_hash(a) } || '?'
    end
  end

  def format_swap_amount(amount)
    return '0' if amount.nil?
    n = amount.to_i
    if n > 10**18
      '%.4f' % (n.to_f / 10**18)
    elsif n > 10**6
      '%.2f' % (n.to_f / 10**6)
    else
      format_number(n)
    end
  end

  def address_page
    <<~HTML
      <div class="page-header">
        <div>
          <div class="page-title">🔍 Address Lookup</div>
          <div class="page-subtitle">Monitor wallet deposits & withdrawals across indexed blocks</div>
        </div>
      </div>

      <div class="address-search-box">
        <div class="form-group">
          <label class="form-label">Wallet Addresses (comma-separated, max 50)</label>
          <textarea class="form-input" id="addr-input" rows="3" placeholder="0xabc123..., 0xdef456...&#10;One address per line or comma-separated" style="resize:vertical;font-family:'SF Mono',Consolas,monospace;font-size:12px">#{h params[:addresses].to_s}</textarea>
        </div>
        <div class="form-row" style="grid-template-columns: 1fr 1fr 1fr 1fr auto;">
          <div class="form-group">
            <label class="form-label">Chain</label>
            <select class="form-input" id="addr-chain">
              #{@chain_configs.map { |c| "<option value=\"#{c.chain_id}\" #{c.chain_id == @stats[:chain_id] ? 'selected' : ''}>#{h c.name} (#{c.chain_id})</option>" }.join}
            </select>
          </div>
          <div class="form-group">
            <label class="form-label">Type</label>
            <select class="form-input" id="addr-type">
              <option value="">All</option>
              <option value="native">Native</option>
              <option value="erc20">ERC-20</option>
              <option value="erc721">ERC-721</option>
              <option value="erc1155">ERC-1155</option>
              <option value="internal">Internal</option>
              <option value="withdrawal">Withdrawal</option>
            </select>
          </div>
          <div class="form-group">
            <label class="form-label">Direction</label>
            <select class="form-input" id="addr-direction">
              <option value="">All</option>
              <option value="in">↓ Incoming</option>
              <option value="out">↑ Outgoing</option>
              <option value="self">↔ Self</option>
            </select>
          </div>
          <div class="form-group">
            <label class="form-label">Limit</label>
            <select class="form-input" id="addr-limit">
              <option value="50">50</option>
              <option value="100" selected>100</option>
              <option value="200">200</option>
              <option value="500">500</option>
            </select>
          </div>
          <div class="form-group" style="display:flex;align-items:flex-end">
            <button class="btn btn-primary" onclick="searchAddresses()" id="addr-search-btn">Search</button>
          </div>
        </div>
      </div>

      <div id="addr-status" style="margin:16px 0;font-size:13px;color:#8b949e;display:none"></div>

      <div id="addr-summary" style="display:none;margin-bottom:16px;">
        <div class="stats-grid" id="addr-stats"></div>
      </div>

      <div class="section">
        <div id="addr-results">
          <div class="empty">Enter wallet addresses above and click Search</div>
        </div>
      </div>

      <div id="addr-pagination" style="display:none;margin-top:12px;display:flex;gap:8px;justify-content:center">
        <button class="btn btn-sm btn-outline" id="addr-prev" onclick="addrPagePrev()">← Prev</button>
        <span id="addr-page-info" style="color:#8b949e;font-size:12px;line-height:28px"></span>
        <button class="btn btn-sm btn-outline" id="addr-next" onclick="addrPageNext()">Next →</button>
      </div>
    HTML
  end

  def h(str)
    ERB::Util.html_escape(str)
  end
end
