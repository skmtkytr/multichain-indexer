class DashboardController < ApplicationController
  def index
    @chain_configs = ChainConfig.order(:chain_id)
    chain_id = params.fetch(:chain_id, @chain_configs.first&.chain_id || 1).to_i
    @current_chain = @chain_configs.find { |c| c.chain_id == chain_id } || @chain_configs.first
    @explorer = @current_chain&.explorer_url&.chomp("/")
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

    @page = params.fetch(:page, "overview")

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
        <style>#{css}</style>
      </head>
      <body>
        <div class="layout">
          #{sidebar}
          <main class="main">
            #{@page == "chains" ? chains_page : overview_page}
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
    CSS
  end

  def sidebar
    mainnet_chains = @chain_configs.select { |c| c.network_type == "mainnet" }
    testnet_chains = @chain_configs.select { |c| c.network_type != "mainnet" }

    chain_items = ""
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
        <a class="nav-item #{@page != 'chains' ? 'active' : ''}" href="/?chain_id=#{@stats[:chain_id]}">📊 Overview</a>
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

  def chains_page
    cards = ""
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
            <div class="form-group">
              <label class="form-label">Network Type</label>
              <select class="form-input" id="f-network-type">
                <option value="mainnet">Mainnet</option>
                <option value="testnet">Testnet</option>
                <option value="devnet">Devnet</option>
              </select>
            </div>
            <div class="form-group">
              <label class="form-label">RPC URL *</label>
              <input class="form-input" id="f-rpc-url" type="url" placeholder="https://bsc-dataseed.binance.org">
              <div class="form-hint">HTTPS endpoint for JSON-RPC. Alchemy/Infura URLs with API keys supported.</div>
            </div>
            <div class="form-group">
              <label class="form-label">Fallback RPC URL</label>
              <input class="form-input" id="f-rpc-fallback" type="url" placeholder="Optional backup endpoint">
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
            <div class="form-group">
              <div class="form-check">
                <input type="checkbox" id="f-enabled" checked>
                <label class="form-label" for="f-enabled" style="margin:0">Enabled</label>
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
      function showAddModal() {
        document.getElementById('modalMode').value = 'add';
        document.getElementById('modalTitle').textContent = 'Add Chain';
        document.getElementById('f-chain-id').value = '';
        document.getElementById('f-chain-id').disabled = false;
        document.getElementById('f-name').value = '';
        document.getElementById('f-network-type').value = 'mainnet';
        document.getElementById('f-rpc-url').value = '';
        document.getElementById('f-rpc-fallback').value = '';
        document.getElementById('f-explorer').value = '';
        document.getElementById('f-currency').value = 'ETH';
        document.getElementById('f-block-time').value = '12000';
        document.getElementById('f-poll-interval').value = '2';
        document.getElementById('f-batch-size').value = '10';
        document.getElementById('f-enabled').checked = true;
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
          document.getElementById('f-name').value = c.name;
          document.getElementById('f-network-type').value = c.network_type || 'mainnet';
          // For edit, fetch full RPC URL from a separate hidden endpoint or just leave masked
          document.getElementById('f-rpc-url').value = '';
          document.getElementById('f-rpc-url').placeholder = c.rpc_url + ' (leave blank to keep)';
          document.getElementById('f-rpc-fallback').value = '';
          document.getElementById('f-explorer').value = c.explorer_url || '';
          document.getElementById('f-currency').value = c.native_currency;
          document.getElementById('f-block-time').value = c.block_time_ms;
          document.getElementById('f-poll-interval').value = c.poll_interval_seconds;
          document.getElementById('f-batch-size').value = c.blocks_per_batch;
          document.getElementById('f-enabled').checked = c.enabled;
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
        body.name = document.getElementById('f-name').value;
        body.network_type = document.getElementById('f-network-type').value;
        const rpc = document.getElementById('f-rpc-url').value;
        if (rpc) body.rpc_url = rpc;
        const fallback = document.getElementById('f-rpc-fallback').value;
        if (fallback) body.rpc_url_fallback = fallback;
        body.explorer_url = document.getElementById('f-explorer').value || null;
        body.native_currency = document.getElementById('f-currency').value;
        body.block_time_ms = parseInt(document.getElementById('f-block-time').value);
        body.poll_interval_seconds = parseInt(document.getElementById('f-poll-interval').value);
        body.blocks_per_batch = parseInt(document.getElementById('f-batch-size').value);
        body.enabled = document.getElementById('f-enabled').checked;

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

      // Auto-refresh on overview (not chains page)
      if (!window.location.search.includes('page=chains')) {
        setTimeout(() => location.reload(), 10000);
      }
    JS
  end

  def chain_card(c)
    cursor = IndexerCursor.find_by(chain_id: c.chain_id)
    status = cursor&.status || "not_initialized"
    badge_class = case c.network_type
                  when "mainnet" then "badge-mainnet"
                  when "testnet" then "badge-testnet"
                  else "badge-devnet"
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
          <div class="chain-card-row"><span class="chain-card-label">RPC</span><span class="chain-card-value" title="#{h c.rpc_url}">#{h c.rpc_url}</span></div>
          #{c.rpc_url_fallback.present? ? "<div class=\"chain-card-row\"><span class=\"chain-card-label\">Fallback</span><span class=\"chain-card-value\">#{h c.rpc_url_fallback}</span></div>" : ''}
          <div class="chain-card-row"><span class="chain-card-label">Currency</span><span class="chain-card-value">#{h c.native_currency}</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Block Time</span><span class="chain-card-value">#{c.block_time_ms}ms</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Poll Interval</span><span class="chain-card-value">#{c.poll_interval_seconds}s</span></div>
          <div class="chain-card-row"><span class="chain-card-label">Batch Size</span><span class="chain-card-value">#{c.blocks_per_batch}</span></div>
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
    status = cursor&.status || "not_initialized"
    active = c.chain_id == @stats[:chain_id] && @page != "chains" ? "active" : ""
    <<~ITEM
      <a class="nav-chain #{active}" href="/?chain_id=#{c.chain_id}">
        <span class="nav-chain-name"><span class="dot #{status}"></span> #{h c.name}</span>
        <span style="color:#484f58;font-size:10px">#{c.chain_id}</span>
      </a>
    ITEM
  end

  def error_banner
    return "" unless @cursor&.error_message.present?
    %(<div class="error-banner">⚠️ #{h @cursor.error_message}</div>)
  end

  def blocks_table
    return %(<div class="empty">No blocks indexed yet</div>) if @blocks.empty?
    rows = @blocks.map do |b|
      "<tr><td>#{link_block(b.number)}</td><td>#{link_block_hash(b.block_hash, b.number)}</td><td>#{Time.at(b.timestamp).utc.strftime('%Y-%m-%d %H:%M:%S')}</td><td>#{link_address(b.miner)}</td><td class=\"num\">#{b.transaction_count}</td><td class=\"num\">#{format_number(b.gas_used)}</td></tr>"
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
    return "—" if hash.blank?
    "#{hash[0..7]}...#{hash[-6..]}"
  end

  def link_block(number)
    return "—" if number.nil?
    if @explorer
      "<a href=\"#{@explorer}/block/#{number}\" target=\"_blank\" class=\"num\">#{number}</a>"
    else
      "<span class=\"num\">#{number}</span>"
    end
  end

  def link_tx(hash)
    return "—" if hash.blank?
    display = truncate_hash(hash)
    if @explorer
      "<a href=\"#{@explorer}/tx/#{hash}\" target=\"_blank\" class=\"hash\" title=\"#{hash}\">#{display}</a>"
    else
      "<span class=\"hash\" title=\"#{hash}\">#{display}</span>"
    end
  end

  def link_address(addr)
    return "—" if addr.blank?
    display = truncate_hash(addr)
    if @explorer
      "<a href=\"#{@explorer}/address/#{addr}\" target=\"_blank\" class=\"addr\" title=\"#{addr}\">#{display}</a>"
    else
      "<span class=\"addr\" title=\"#{addr}\">#{display}</span>"
    end
  end

  def link_block_hash(hash, number)
    return "—" if hash.blank?
    display = truncate_hash(hash)
    if @explorer
      "<a href=\"#{@explorer}/block/#{number}\" target=\"_blank\" class=\"hash\" title=\"#{hash}\">#{display}</a>"
    else
      "<span class=\"hash\" title=\"#{hash}\">#{display}</span>"
    end
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

  def h(str)
    ERB::Util.html_escape(str)
  end
end
