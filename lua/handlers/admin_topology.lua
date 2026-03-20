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
      --bg: #f3f6fc;
      --panel: #fff;
      --panel-soft: #f8fbff;
      --text: #0f172a;
      --muted: #64748b;
      --line: #d9e2f1;
      --brand: #2563eb;
      --ok: #059669;
      --warn: #d97706;
      --bad: #dc2626;
      --shadow: 0 12px 28px rgba(15, 23, 42, 0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background:
        radial-gradient(1200px 500px at 0% 0%, #e7f0ff 0%, rgba(231,240,255,0) 60%),
        radial-gradient(1000px 380px at 100% 0%, #e8fff9 0%, rgba(232,255,249,0) 58%),
        var(--bg);
      color: var(--text);
      font-family: Inter, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    }
    .wrap {
      max-width: 1320px;
      margin: 0 auto;
      padding: 20px 20px 26px;
    }
    .head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      flex-wrap: wrap;
      margin-bottom: 14px;
    }
    .title { margin: 0; font-size: 26px; font-weight: 800; letter-spacing: -0.02em; }
    .sub { margin-top: 6px; color: var(--muted); font-size: 13px; }
    .tabs {
      display: inline-flex;
      border: 1px solid var(--line);
      border-radius: 999px;
      overflow: hidden;
      background: var(--panel);
      box-shadow: var(--shadow);
    }
    .tabs a {
      text-decoration: none;
      color: #334155;
      padding: 8px 15px;
      font-size: 13px;
      border-right: 1px solid var(--line);
      transition: all .2s ease;
    }
    .tabs a:last-child { border-right: 0; }
    .tabs a.active {
      background: linear-gradient(135deg, #2e6ef7 0%, #2563eb 100%);
      color: #fff;
      font-weight: 600;
    }
    .controls {
      display: flex;
      gap: 10px;
      align-items: center;
      flex-wrap: wrap;
      margin-bottom: 16px;
      padding: 12px;
      border: 1px solid var(--line);
      border-radius: 14px;
      background: rgba(255,255,255,0.72);
      backdrop-filter: blur(4px);
    }
    .controls label {
      font-size: 12px;
      color: var(--muted);
      font-weight: 600;
    }
    input, select {
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 7px 10px;
      font-size: 13px;
      background: #fff;
      color: var(--text);
    }
    input { min-width: 240px; }
    .updated { margin-left: auto; font-size: 12px; color: var(--muted); }
    .card-grid {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: 12px;
      margin-bottom: 14px;
    }
    .card {
      border: 1px solid var(--line);
      border-radius: 14px;
      background: var(--panel);
      padding: 12px;
      box-shadow: var(--shadow);
    }
    .card.accent {
      background: linear-gradient(135deg, #2363eb 0%, #2e72ff 100%);
      color: #f8fbff;
      border-color: transparent;
    }
    .k { font-size: 12px; color: var(--muted); }
    .card.accent .k { color: rgba(248,251,255,0.88); }
    .v {
      font-size: 26px;
      line-height: 1.15;
      font-weight: 800;
      margin-top: 8px;
      letter-spacing: -0.02em;
    }
    .hint { margin-top: 6px; font-size: 12px; color: var(--muted); }
    .card.accent .hint { color: rgba(248,251,255,0.82); }
    .layout-grid {
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 12px;
    }
    .section {
      border: 1px solid var(--line);
      border-radius: 14px;
      background: var(--panel);
      padding: 14px;
      box-shadow: var(--shadow);
    }
    .section h3 { margin: 0; font-size: 16px; font-weight: 700; letter-spacing: -0.01em; }
    .section-sub {
      margin-top: 4px;
      margin-bottom: 10px;
      color: var(--muted);
      font-size: 12px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      text-align: left;
      border-bottom: 1px solid var(--line);
      padding: 8px 6px;
      vertical-align: top;
    }
    th { color: var(--muted); font-weight: 600; font-size: 12px; }
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
    .ok { color: var(--ok); }
    .bad { color: var(--bad); }
    .warn { color: var(--warn); }
    .muted { color: var(--muted); font-size: 12px; }
    .chip-list { display: flex; gap: 8px; flex-wrap: wrap; }
    .chip {
      border: 1px solid var(--line);
      border-radius: 999px;
      background: var(--panel-soft);
      padding: 4px 10px;
      font-size: 12px;
    }
    .rate-badge {
      display: inline-block;
      border-radius: 999px;
      padding: 2px 8px;
      font-size: 12px;
      font-weight: 600;
    }
    .ok-bg { background: #dcfce7; color: #166534; }
    .warn-bg { background: #fef3c7; color: #92400e; }
    .bad-bg { background: #fee2e2; color: #991b1b; }
    .bar {
      height: 8px;
      border-radius: 999px;
      background: #e5edf8;
      overflow: hidden;
      margin-top: 6px;
    }
    .bar > i {
      display: block;
      height: 100%;
      background: linear-gradient(90deg, #6ea2ff 0%, #2563eb 100%);
    }
    .table-wrap {
      overflow: auto;
      border: 1px solid var(--line);
      border-radius: 10px;
    }
    .footer-note {
      margin-top: 10px;
      font-size: 12px;
      color: var(--muted);
    }
    @media (max-width: 1220px) {
      .card-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); }
      .layout-grid { grid-template-columns: 1fr; }
    }
    @media (max-width: 760px) {
      .card-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .updated { width: 100%; margin-left: 0; }
    }
    @media (max-width: 520px) {
      .card-grid { grid-template-columns: 1fr; }
      input { min-width: 100%; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="head">
      <div>
        <div class="title">LLM Gateway 模型与渠道</div>
        <div class="sub">资源拓扑与集成状态</div>
      </div>
      <div class="tabs">
        <a href="/admin/dashboard" id="tab_overview">概览</a>
        <a href="/admin/dashboard/topology" class="active" id="tab_topology">模型与渠道</a>
        <a href="/admin/dashboard/config" id="tab_config">配置中心</a>
      </div>
    </div>

    <div class="controls">
      <label>统计窗口</label>
      <select id="window_minutes">
        <option value="15">最近 15 分钟</option>
        <option value="60" selected>最近 60 分钟</option>
        <option value="360">最近 6 小时</option>
        <option value="1440">最近 24 小时</option>
      </select>
      <label>筛选</label>
      <input id="search" type="text" placeholder="模型 / 渠道" />
      <span id="updated" class="updated">更新时间: --</span>
    </div>

    <div class="card-grid">
      <div class="card accent"><div class="k">模型数</div><div class="v" id="c_models">0</div><div class="hint">当前可路由模型</div></div>
      <div class="card"><div class="k">Provider 数</div><div class="v" id="c_providers">0</div><div class="hint">可用渠道数量</div></div>
      <div class="card"><div class="k">网关 Key（启用/总数）</div><div class="v" id="c_keys">0 / 0</div><div class="hint">客户端鉴权 Key</div></div>
      <div class="card"><div class="k">窗口调用量</div><div class="v" id="c_calls">0</div><div class="hint">与窗口选择联动</div></div>
    </div>

    <div class="layout-grid">
      <div class="section">
        <h3>模型矩阵</h3>
        <div class="section-sub">展示模型别名、默认渠道、可用渠道与真实映射关系</div>
        <div class="table-wrap">
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
      </div>

      <div class="section">
        <h3>集成状态</h3>
        <div class="section-sub">运行时开关与关键元数据</div>
        <div id="integrations" class="chip-list">
          <div class="chip"><strong>Gateway 鉴权</strong>: <span class="muted">加载中...</span></div>
          <div class="chip"><strong>Admin Token</strong>: <span class="muted">加载中...</span></div>
        </div>
      </div>
    </div>

    <div class="section" style="margin-top:12px;">
      <h3>渠道健康榜</h3>
      <div class="section-sub">按失败数排序，快速定位高风险 Provider</div>
      <div class="table-wrap">
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
              <th>流量占比</th>
            </tr>
          </thead>
          <tbody id="provider_rows"></tbody>
        </table>
      </div>
    </div>

    <div class="footer-note">数据来源: <code>/admin/catalog</code> + <code>/admin/stats</code>（窗口统计）</div>
  </div>

  <script>
    const fmt = (n) => Number(n || 0).toLocaleString();
    const pct = (n) => Number(n || 0).toFixed(2) + '%';
    const state = { catalog: null, stats: null };

    function badgeClass(rateNum) {
      if (rateNum >= 10) return 'rate-badge bad-bg';
      if (rateNum >= 3) return 'rate-badge warn-bg';
      return 'rate-badge ok-bg';
    }

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
      const config = document.getElementById('tab_config');
      overview.href = '/admin/dashboard?admin_token=' + encodeURIComponent(t);
      topology.href = '/admin/dashboard/topology?admin_token=' + encodeURIComponent(t);
      config.href = '/admin/dashboard/config?admin_token=' + encodeURIComponent(t);
    }

    function renderCards() {
      const catalog = state.catalog || {};
      const summary = catalog.summary || {};
      const stats = state.stats || {};
      const windowTotals = stats.window_totals || {};
      const totals = stats.totals || {};
      document.getElementById('c_models').textContent = fmt(summary.models);
      document.getElementById('c_providers').textContent = fmt(summary.providers);
      document.getElementById('c_keys').textContent = fmt(summary.gateway_keys_enabled) + ' / ' + fmt(summary.gateway_keys_total);
      document.getElementById('c_calls').textContent = fmt(windowTotals.total);
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
        const defaults = (m.default_providers || []);
        const def = defaults.length
          ? '<span class="ok">' + defaults.join(' → ') + '</span>'
          : (m.default_provider ? '<span class="ok">' + m.default_provider + '</span>' : '<span class="warn">未设置</span>');
        return '<tr>' +
          '<td><strong>' + m.id + '</strong><div class="muted">alias: ' + (m.aliases || []).join(', ') + '</div></td>' +
          '<td>' + def + '</td>' +
          '<td>' + (allow || '<span class="muted">未限制</span>') + '</td>' +
          '<td>' + map + '</td>' +
        '</tr>';
      }).join('');
      if (!filtered.length) {
        tbody.innerHTML = '<tr><td colspan="4" class="muted">无匹配结果</td></tr>';
      }
    }

    function renderProviders() {
      const providers = ((state.catalog || {}).providers) || [];
      const totals = (((state.stats || {}).window_totals) || {});
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
        const rateNum = total > 0 ? ((fail / total) * 100) : 0;
        return {
          name: p.name,
          weight: p.weight || 1,
          keyCount: p.key_count || 0,
          cooldownKeys: Number(cooldownByProvider[p.name] || 0),
          timeout: p.timeout_ms || 0,
          total,
          fail,
          rateNum: rateNum,
        };
      }).sort((a, b) => b.fail - a.fail || b.rateNum - a.rateNum || b.total - a.total).slice(0, 20);

      const tbody = document.getElementById('provider_rows');
      const totalCalls = rows.reduce((s, r) => s + r.total, 0) || 1;
      tbody.innerHTML = rows.map((r) => {
        const share = Math.round((r.total / totalCalls) * 100);
        return '<tr>' +
          '<td><strong>' + r.name + '</strong></td>' +
          '<td>' + r.weight + '</td>' +
          '<td>' + r.keyCount + '</td>' +
          '<td>' + r.cooldownKeys + '</td>' +
          '<td>' + fmt(r.timeout) + ' ms</td>' +
          '<td>' + fmt(r.total) + '</td>' +
          '<td>' + fmt(r.fail) + '</td>' +
          '<td><span class="' + badgeClass(r.rateNum) + '">' + pct(r.rateNum) + '</span></td>' +
          '<td><div class="bar"><i style="width:' + share + '%"></i></div></td>' +
        '</tr>';
      }).join('');
      if (!rows.length) {
        tbody.innerHTML = '<tr><td colspan="9" class="muted">暂无渠道数据</td></tr>';
      }
    }

    function renderIntegrations() {
      try {
        const runtime = ((state.catalog || {}).runtime) || {};
        const summary = ((state.catalog || {}).summary) || {};
        const blocks = [
          ['Gateway 鉴权', runtime.auth_enabled ? '已启用' : '未启用', runtime.auth_enabled ? 'ok' : 'warn'],
          ['Admin Token', runtime.admin_token_enabled ? '已启用' : '未启用', runtime.admin_token_enabled ? 'ok' : 'warn'],
          ['选择头暴露', runtime.expose_selection_headers ? '已启用' : '未启用', runtime.expose_selection_headers ? 'ok' : 'muted'],
          ['热更新间隔', String(runtime.reload_interval_sec || 0) + ' 秒', 'muted'],
          ['租户数量', fmt(summary.tenants), 'muted'],
        ];
        document.getElementById('integrations').innerHTML = blocks.map((b) => {
          return '<div class="chip"><strong>' + b[0] + '</strong>: <span class="' + b[2] + '">' + b[1] + '</span></div>';
        }).join('');
      } catch (e) {
        document.getElementById('integrations').innerHTML =
          '<div class="chip"><strong>集成状态</strong>: <span class="bad">加载失败</span></div>';
      }
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
      renderIntegrations();
      renderModels();
      renderProviders();
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
