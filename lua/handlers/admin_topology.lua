local admin_auth = require('core.admin_auth')

ngx.ctx.skip_stats = true

if not admin_auth.guard() then
  return
end

ngx.header['Content-Type'] = 'text/html; charset=utf-8'

ngx.say([[
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>LLM Gateway 资源拓扑</title>
  <style>
    :root {
      --bg: #f3f5f8;
      --panel: #ffffff;
      --text: #0f172a;
      --muted: #64748b;
      --line: #dbe2ea;
      --primary: #0f766e;
      --warn: #b45309;
      --bad: #b91c1c;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: radial-gradient(circle at 10% 0%, #e8f7f4 0, #f3f5f8 40%);
      color: var(--text);
      font-family: "Segoe UI", "PingFang SC", "Hiragino Sans GB", sans-serif;
    }
    .wrap {
      max-width: 1200px;
      margin: 0 auto;
      padding: 20px;
    }
    .head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 12px;
      flex-wrap: wrap;
    }
    .title { font-size: 24px; font-weight: 700; }
    .sub { color: var(--muted); font-size: 13px; }
    .tabs {
      display: inline-flex;
      border: 1px solid var(--line);
      border-radius: 999px;
      overflow: hidden;
      background: #fff;
    }
    .tabs a {
      text-decoration: none;
      color: #334155;
      padding: 7px 14px;
      font-size: 13px;
      border-right: 1px solid var(--line);
    }
    .tabs a:last-child { border-right: 0; }
    .tabs a.active { background: #0f766e; color: #fff; }
    .controls {
      display: flex;
      gap: 8px;
      align-items: center;
      flex-wrap: wrap;
      margin-bottom: 12px;
    }
    .card-grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      margin-bottom: 12px;
    }
    .card {
      border: 1px solid var(--line);
      border-radius: 12px;
      background: var(--panel);
      padding: 12px;
    }
    .k { color: var(--muted); font-size: 12px; }
    .v { font-size: 24px; font-weight: 700; margin-top: 6px; }
    .section {
      border: 1px solid var(--line);
      border-radius: 12px;
      background: var(--panel);
      padding: 12px;
      margin-bottom: 12px;
    }
    .section h3 {
      margin: 0 0 8px;
      font-size: 16px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      text-align: left;
      border-bottom: 1px solid var(--line);
      padding: 7px 4px;
      vertical-align: top;
    }
    th { color: var(--muted); font-weight: 600; }
    .pill {
      display: inline-block;
      border: 1px solid var(--line);
      border-radius: 999px;
      background: #fff;
      padding: 2px 8px;
      margin-right: 6px;
      margin-bottom: 4px;
      font-size: 12px;
    }
    .ok { color: var(--primary); }
    .bad { color: var(--bad); }
    .warn { color: var(--warn); }
    input, select {
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 6px 8px;
      font-size: 13px;
      background: #fff;
    }
    .muted { color: var(--muted); font-size: 12px; }
    @media (max-width: 980px) {
      .card-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    }
    @media (max-width: 640px) {
      .card-grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="head">
      <div>
        <div class="title">LLM Gateway 模型与渠道</div>
        <div class="sub">资源拓扑与集成状态（轻量模式）</div>
      </div>
      <div class="tabs">
        <a href="/admin/dashboard" id="tab_overview">概览</a>
        <a href="/admin/dashboard/topology" class="active" id="tab_topology">模型与渠道</a>
      </div>
    </div>

    <div class="controls">
      <label>窗口</label>
      <select id="window_minutes">
        <option value="15">15m</option>
        <option value="60" selected>60m</option>
        <option value="360">6h</option>
        <option value="1440">24h</option>
      </select>
      <label>筛选</label>
      <input id="search" type="text" placeholder="模型 / 渠道" />
      <span id="updated" class="muted">更新时间: --</span>
    </div>

    <div class="card-grid">
      <div class="card"><div class="k">模型数</div><div class="v" id="c_models">0</div></div>
      <div class="card"><div class="k">渠道数</div><div class="v" id="c_providers">0</div></div>
      <div class="card"><div class="k">网关 Key（启用/总数）</div><div class="v" id="c_keys">0 / 0</div></div>
      <div class="card"><div class="k">最近窗口调用量</div><div class="v" id="c_calls">0</div></div>
    </div>

    <div class="section">
      <h3>模型矩阵</h3>
      <table>
        <thead>
          <tr>
            <th>模型</th>
            <th>默认渠道</th>
            <th>可用渠道</th>
            <th>映射</th>
          </tr>
        </thead>
        <tbody id="model_rows"></tbody>
      </table>
    </div>

    <div class="section">
      <h3>渠道健康榜（按最近窗口失败数）</h3>
      <table>
        <thead>
          <tr>
            <th>渠道</th>
            <th>权重</th>
            <th>Key数</th>
            <th>Cooldown中Key</th>
            <th>超时</th>
            <th>调用</th>
            <th>失败</th>
            <th>失败率</th>
          </tr>
        </thead>
        <tbody id="provider_rows"></tbody>
      </table>
    </div>

    <div class="section">
      <h3>集成状态</h3>
      <div id="integrations"></div>
    </div>
  </div>

  <script>
    const fmt = (n) => Number(n || 0).toLocaleString();
    const state = { catalog: null, stats: null };

    function withToken(url) {
      const params = new URLSearchParams(window.location.search);
      const t = params.get('admin_token');
      if (t) url.searchParams.set('admin_token', t);
      return url;
    }

    function updateTabLinks() {
      const params = new URLSearchParams(window.location.search);
      const t = params.get('admin_token');
      if (!t) return;
      const overview = document.getElementById('tab_overview');
      const topology = document.getElementById('tab_topology');
      overview.href = '/admin/dashboard?admin_token=' + encodeURIComponent(t);
      topology.href = '/admin/dashboard/topology?admin_token=' + encodeURIComponent(t);
    }

    function renderCards() {
      const catalog = state.catalog || {};
      const summary = catalog.summary || {};
      const stats = state.stats || {};
      const totals = stats.totals || {};
      document.getElementById('c_models').textContent = fmt(summary.models);
      document.getElementById('c_providers').textContent = fmt(summary.providers);
      document.getElementById('c_keys').textContent = fmt(summary.gateway_keys_enabled) + ' / ' + fmt(summary.gateway_keys_total);
      document.getElementById('c_calls').textContent = fmt(totals.total);
      document.getElementById('updated').textContent = '更新时间: ' + new Date().toLocaleString();
    }

    function renderModels() {
      const q = (document.getElementById('search').value || '').trim().toLowerCase();
      const rows = (state.catalog && state.catalog.models) || [];
      const filtered = rows.filter((m) => {
        if (!q) return true;
        const p = Object.keys(m.provider_map || {}).join(' ').toLowerCase();
        const a = (m.aliases || []).join(' ').toLowerCase();
        return (m.id || '').toLowerCase().includes(q) || p.includes(q) || a.includes(q);
      });
      const tbody = document.getElementById('model_rows');
      tbody.innerHTML = filtered.map((m) => {
        const allow = (m.allow_providers || []).map((x) => '<span class="pill">' + x + '</span>').join(' ');
        const map = Object.entries(m.provider_map || {}).map(([k, v]) => '<div><span class="pill">' + k + '</span>' + v + '</div>').join('');
        const def = m.default_provider ? '<span class="ok">' + m.default_provider + '</span>' : '<span class="warn">未设置</span>';
        return '<tr>' +
          '<td><strong>' + m.id + '</strong><div class="muted">alias: ' + (m.aliases || []).join(', ') + '</div></td>' +
          '<td>' + def + '</td>' +
          '<td>' + allow + '</td>' +
          '<td>' + map + '</td>' +
        '</tr>';
      }).join('');
      if (!filtered.length) {
        tbody.innerHTML = '<tr><td colspan="4" class="muted">无匹配结果</td></tr>';
      }
    }

    function renderProviders() {
      const providers = ((state.catalog || {}).providers) || [];
      const totals = (((state.stats || {}).totals) || {});
      const byProvider = totals.by_provider || {};
      const byFailure = totals.by_provider_failure || {};
      const keyStats = state.stats && state.stats.key_stats ? state.stats.key_stats : [];
      const cooldownByProvider = {};
      keyStats.forEach((k) => {
        if (Number(k.current_cooldown_ttl || 0) > 0) {
          cooldownByProvider[k.provider] = Number(cooldownByProvider[k.provider] || 0) + 1;
        }
      });
      const rows = providers.map((p) => {
        const total = Number(byProvider[p.name] || 0);
        const fail = Number(byFailure[p.name] || 0);
        const rate = total > 0 ? ((fail / total) * 100).toFixed(2) : '0.00';
        return {
          name: p.name,
          weight: p.weight || 1,
          keyCount: p.key_count || 0,
          cooldownKeys: Number(cooldownByProvider[p.name] || 0),
          timeout: p.timeout_ms || 0,
          total,
          fail,
          rateNum: total > 0 ? fail / total : 0,
          rate,
        };
      }).sort((a, b) => b.fail - a.fail || b.rateNum - a.rateNum || b.total - a.total);

      const tbody = document.getElementById('provider_rows');
      tbody.innerHTML = rows.map((r) => {
        const rateClass = r.rateNum >= 0.1 ? 'bad' : (r.rateNum >= 0.03 ? 'warn' : 'ok');
        return '<tr>' +
          '<td><strong>' + r.name + '</strong></td>' +
          '<td>' + r.weight + '</td>' +
          '<td>' + r.keyCount + '</td>' +
          '<td>' + r.cooldownKeys + '</td>' +
          '<td>' + fmt(r.timeout) + ' ms</td>' +
          '<td>' + fmt(r.total) + '</td>' +
          '<td>' + fmt(r.fail) + '</td>' +
          '<td class="' + rateClass + '">' + r.rate + '%</td>' +
        '</tr>';
      }).join('');
      if (!rows.length) {
        tbody.innerHTML = '<tr><td colspan="8" class="muted">暂无渠道数据</td></tr>';
      }
    }

    function renderIntegrations() {
      const runtime = ((state.catalog || {}).runtime) || {};
      const summary = ((state.catalog || {}).summary) || {};
      const blocks = [
        ['Gateway 鉴权', runtime.auth_enabled ? '已启用' : '未启用', runtime.auth_enabled ? 'ok' : 'warn'],
        ['Admin Token', runtime.admin_token_enabled ? '已启用' : '未启用', runtime.admin_token_enabled ? 'ok' : 'warn'],
        ['选择头暴露', runtime.expose_selection_headers ? '已启用' : '未启用', runtime.expose_selection_headers ? 'ok' : 'muted'],
        ['热更新间隔', String(runtime.reload_interval_sec || 0) + ' 秒', 'muted'],
        ['配置 Hash', runtime.config_hash || '-', 'muted'],
        ['租户数量', fmt(summary.tenants), 'muted'],
      ];
      document.getElementById('integrations').innerHTML = blocks.map((b) => {
        return '<div class="pill"><strong>' + b[0] + '</strong>: <span class="' + b[2] + '">' + b[1] + '</span></div>';
      }).join('');
    }

    async function refresh() {
      if (document.hidden) return;
      const windowMinutes = document.getElementById('window_minutes').value;
      const catalogUrl = withToken(new URL('/admin/catalog', window.location.origin));
      const statsUrl = withToken(new URL('/admin/stats', window.location.origin));
      statsUrl.searchParams.set('window', windowMinutes);

      const [catalogRes, statsRes] = await Promise.all([
        fetch(catalogUrl.toString(), { cache: 'no-store' }),
        fetch(statsUrl.toString(), { cache: 'no-store' }),
      ]);
      if (!catalogRes.ok || !statsRes.ok) return;

      state.catalog = await catalogRes.json();
      state.stats = await statsRes.json();
      renderCards();
      renderModels();
      renderProviders();
      renderIntegrations();
    }

    document.getElementById('search').addEventListener('input', renderModels);
    document.getElementById('window_minutes').addEventListener('change', refresh);
    document.addEventListener('visibilitychange', refresh);

    updateTabLinks();
    refresh();
    setInterval(refresh, 10000);
  </script>
</body>
</html>
]])
