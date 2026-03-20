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
  <title>LLM Gateway 控制台</title>
  <style>
    :root {
      --bg: #f3f6fc;
      --panel: #ffffff;
      --panel-soft: #f8faff;
      --text: #0f172a;
      --muted: #64748b;
      --line: #d9e2f1;
      --brand: #2563eb;
      --brand-soft: #dbeafe;
      --ok: #059669;
      --warn: #d97706;
      --bad: #dc2626;
      --shadow: 0 12px 28px rgba(15, 23, 42, 0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background:
        radial-gradient(1200px 500px at 0% 0%, #e7f0ff 0%, rgba(231,240,255,0) 60%),
        radial-gradient(1000px 380px at 100% 0%, #e8fff9 0%, rgba(232,255,249,0) 58%),
        var(--bg);
      color: var(--text);
      font-family: Inter, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    }
    .layout {
      max-width: 1320px;
      margin: 0 auto;
      padding: 20px 20px 26px;
    }
    .topbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      margin-bottom: 14px;
      flex-wrap: wrap;
    }
    .title {
      margin: 0;
      font-size: 26px;
      font-weight: 800;
      letter-spacing: -0.02em;
    }
    .subtitle {
      margin-top: 6px;
      color: var(--muted);
      font-size: 13px;
    }
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
    .toolbar {
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
    .toolbar label {
      font-size: 12px;
      color: var(--muted);
      font-weight: 600;
    }
    select, button {
      border: 1px solid var(--line);
      border-radius: 10px;
      background: var(--panel);
      color: var(--text);
      padding: 7px 10px;
      font-size: 13px;
    }
    button {
      cursor: pointer;
      transition: all .2s ease;
    }
    button:hover {
      border-color: var(--brand);
      color: var(--brand);
    }
    .updated {
      font-size: 12px;
      color: var(--muted);
      margin-left: auto;
    }
    .cards {
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
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
    .k {
      font-size: 12px;
      color: var(--muted);
    }
    .card.accent .k { color: rgba(248,251,255,0.88); }
    .v {
      font-size: 26px;
      line-height: 1.15;
      font-weight: 800;
      margin-top: 8px;
      letter-spacing: -0.02em;
    }
    .hint {
      margin-top: 6px;
      font-size: 12px;
      color: var(--muted);
    }
    .card.accent .hint { color: rgba(248,251,255,0.82); }
    .grid {
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
    .section h3 {
      margin: 0;
      font-size: 16px;
      font-weight: 700;
      letter-spacing: -0.01em;
    }
    .section-sub {
      margin-top: 4px;
      margin-bottom: 10px;
      color: var(--muted);
      font-size: 12px;
    }
    canvas {
      width: 100%;
      height: 260px;
      display: block;
      border-radius: 10px;
      background: linear-gradient(180deg, #fbfdff 0%, #f7faff 100%);
      border: 1px solid var(--line);
    }
    .legend {
      display: flex;
      gap: 12px;
      margin-bottom: 10px;
      font-size: 12px;
      color: var(--muted);
      flex-wrap: wrap;
    }
    .dot {
      display: inline-block;
      width: 8px;
      height: 8px;
      border-radius: 999px;
      margin-right: 6px;
    }
    .status-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
      margin-top: 10px;
    }
    .status-item {
      border: 1px solid var(--line);
      background: var(--panel-soft);
      border-radius: 10px;
      padding: 8px;
      font-size: 12px;
    }
    .status-item strong {
      display: block;
      font-size: 19px;
      color: var(--text);
      margin-top: 4px;
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
    th {
      color: var(--muted);
      font-weight: 600;
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
    .event-stream {
      max-height: 280px;
      overflow: auto;
      border: 1px solid var(--line);
      border-radius: 10px;
      background: #fbfdff;
    }
    .event-item {
      padding: 8px 10px;
      border-bottom: 1px solid var(--line);
      font-size: 12px;
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: center;
    }
    .event-item:last-child { border-bottom: 0; }
    .event-meta { color: var(--muted); }
    .error-bars {
      margin-top: 8px;
      display: grid;
      gap: 8px;
    }
    .error-row {
      display: grid;
      grid-template-columns: 130px 1fr 56px;
      gap: 8px;
      align-items: center;
      font-size: 12px;
    }
    .footer-note {
      margin-top: 10px;
      font-size: 12px;
      color: var(--muted);
    }
    @media (max-width: 1220px) {
      .cards { grid-template-columns: repeat(3, minmax(0, 1fr)); }
      .grid { grid-template-columns: 1fr; }
    }
    @media (max-width: 760px) {
      .cards { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .status-grid { grid-template-columns: 1fr; }
      .error-row { grid-template-columns: 1fr; }
      .updated { width: 100%; margin-left: 0; }
    }
  </style>
</head>
<body>
  <div class="layout">
    <div class="topbar">
      <div>
        <h1 class="title">LLM Gateway 运行总览</h1>
        <div class="subtitle">
          更聚焦稳定性和可用性的实时可视化视图
        </div>
      </div>
      <div class="tabs">
        <a href="/admin/dashboard" class="active" id="tab_overview">概览</a>
        <a href="/admin/dashboard/topology" id="tab_topology">模型与渠道</a>
        <a href="/admin/dashboard/config" id="tab_config">配置中心</a>
      </div>
    </div>

    <div class="toolbar">
      <label for="window_minutes">统计窗口</label>
      <select id="window_minutes">
        <option value="15">最近 15 分钟</option>
        <option value="60" selected>最近 60 分钟</option>
        <option value="360">最近 6 小时</option>
        <option value="1440">最近 24 小时</option>
      </select>
      <button id="btn_refresh" type="button">立即刷新</button>
      <span class="updated" id="updated">更新时间: --</span>
    </div>

    <div class="cards">
      <div class="card accent">
        <div class="k">窗口调用量</div>
        <div class="v" id="total">0</div>
        <div class="hint" id="qps_hint">峰值分钟调用: 0 · 累计总调用: 0</div>
      </div>
      <div class="card">
        <div class="k">窗口成功率</div>
        <div class="v" id="success_rate">0%</div>
        <div class="hint" id="failure_rate_hint">失败率 0%</div>
      </div>
      <div class="card">
        <div class="k">窗口失败请求</div>
        <div class="v" id="failure">0</div>
        <div class="hint" id="err_hint">错误类型 0 种</div>
      </div>
      <div class="card">
        <div class="k">平均延迟</div>
        <div class="v" id="latency">0 ms</div>
        <div class="hint">单位: 毫秒</div>
      </div>
      <div class="card">
        <div class="k">活跃 Provider</div>
        <div class="v" id="providers">0</div>
        <div class="hint" id="providers_hint">出现失败 0 个</div>
      </div>
      <div class="card">
        <div class="k">Cooldown Key</div>
        <div class="v" id="cooldown_keys">0</div>
        <div class="hint">当前处于冷却中的 Key</div>
      </div>
    </div>

    <div class="grid">
      <div class="section">
        <h3>流量与失败趋势</h3>
        <div class="section-sub">蓝色为总调用，红色为失败数（按分钟聚合）</div>
        <div class="legend">
          <span><i class="dot" style="background:#2563eb"></i>总调用</span>
          <span><i class="dot" style="background:#dc2626"></i>失败数</span>
          <span id="series_hint">采样点: 0</span>
        </div>
        <canvas id="calls"></canvas>
      </div>
      <div class="section">
        <h3>状态码分布</h3>
        <div class="section-sub">观察 2xx/4xx/5xx 的即时占比</div>
        <div class="status-grid" id="status_grid"></div>
      </div>
    </div>

    <div class="grid" style="margin-top:12px;">
      <div class="section">
        <h3>Provider 健康榜</h3>
        <div class="section-sub">按失败数排序，便于快速定位异常渠道 · 未归属请求: <span id="unassigned_requests">0</span></div>
        <table>
          <thead>
            <tr><th>Provider</th><th>总调用</th><th>失败</th><th>失败率</th><th>占比</th></tr>
          </thead>
          <tbody id="provider_rows"></tbody>
        </table>
      </div>
      <div class="section">
        <h3>错误类型分解</h3>
        <div class="section-sub">Top N 错误原因</div>
        <div id="error_bars" class="error-bars"></div>
      </div>
    </div>

    <div class="grid" style="margin-top:12px;">
      <div class="section">
        <h3>Key 风险榜</h3>
        <div class="section-sub">按 429、4xx、Cooldown 事件综合评分</div>
        <table>
          <thead>
            <tr><th>Provider</th><th>Key</th><th>4xx</th><th>429</th><th>Cooldown</th><th>风险分</th></tr>
          </thead>
          <tbody id="key_rows"></tbody>
        </table>
      </div>
      <div class="section">
        <h3>Cooldown 事件流</h3>
        <div class="section-sub">最近 50 条事件</div>
        <div class="event-stream" id="cooldown_rows"></div>
      </div>
    </div>

    <div class="footer-note">数据来源: <code>/admin/stats</code>（内存统计，网关重启后清零）</div>
  </div>
  <script>
    const canvas = document.getElementById('calls');
    const ctx = canvas.getContext('2d');

    function resize() {
      const dpr = window.devicePixelRatio || 1;
      const rect = canvas.getBoundingClientRect();
      canvas.width = Math.floor(rect.width * dpr);
      canvas.height = Math.floor(260 * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function draw(series) {
      resize();
      const w = canvas.getBoundingClientRect().width;
      const h = 260;
      ctx.clearRect(0, 0, w, h);
      if (!series || !series.length) return;

      const pad = 24;
      const cw = w - pad * 2;
      const ch = h - pad * 2;
      let maxY = 1;
      for (const p of series) {
        maxY = Math.max(maxY, p.total || 0, p.failure || 0);
      }

      function x(i) {
        if (series.length === 1) return pad;
        return pad + (i / (series.length - 1)) * cw;
      }
      function y(v) {
        return pad + ch - (v / maxY) * ch;
      }

      ctx.strokeStyle = '#d9e2f1';
      ctx.lineWidth = 1;
      for (let i = 0; i <= 4; i++) {
        const gy = pad + (i / 4) * ch;
        ctx.beginPath();
        ctx.moveTo(pad, gy);
        ctx.lineTo(pad + cw, gy);
        ctx.stroke();
      }

      ctx.strokeStyle = '#2563eb';
      ctx.lineWidth = 2.2;
      ctx.beginPath();
      for (let i = 0; i < series.length; i++) {
        const p = series[i];
        const px = x(i);
        const py = y(p.total || 0);
        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      }
      ctx.stroke();

      ctx.strokeStyle = '#dc2626';
      ctx.lineWidth = 2.2;
      ctx.beginPath();
      for (let i = 0; i < series.length; i++) {
        const p = series[i];
        const px = x(i);
        const py = y(p.failure || 0);
        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      }
      ctx.stroke();
    }

    function fmt(n) {
      return Number(n || 0).toLocaleString();
    }

    function pct(n) {
      return (Number(n || 0)).toFixed(2) + '%';
    }

    function fmtTs(ts) {
      const n = Number(ts || 0);
      if (!n) return '-';
      return new Date(n * 1000).toLocaleString();
    }

    function badgeClass(rate) {
      if (rate >= 10) return 'rate-badge bad-bg';
      if (rate >= 3) return 'rate-badge warn-bg';
      return 'rate-badge ok-bg';
    }

    function statusClass(status) {
      const n = Number(status || 0);
      if (n >= 500) return 'rate-badge bad-bg';
      if (n >= 400) return 'rate-badge warn-bg';
      return 'rate-badge ok-bg';
    }

    function renderStatus(by) {
      const rows = [
        { key: '2xx', label: '2xx 成功', v: Number(by['2xx'] || 0) },
        { key: '3xx', label: '3xx 重定向', v: Number(by['3xx'] || 0) },
        { key: '4xx', label: '4xx 客户端错误', v: Number(by['4xx'] || 0) },
        { key: '5xx', label: '5xx 服务端错误', v: Number(by['5xx'] || 0) },
      ];
      const total = rows.reduce((s, x) => s + x.v, 0) || 1;
      const box = document.getElementById('status_grid');
      box.innerHTML = rows.map((r) => {
        const p = ((r.v / total) * 100).toFixed(1);
        return '<div class="status-item">' +
          '<span>' + r.label + '</span>' +
          '<strong>' + fmt(r.v) + '</strong>' +
          '<div class="hint">' + p + '%</div>' +
        '</div>';
      }).join('');
    }

    function renderErrors(byErr) {
      const rows = Object.entries(byErr || {})
        .sort((a, b) => (b[1] || 0) - (a[1] || 0))
        .slice(0, 8);
      const max = rows.length ? Number(rows[0][1] || 1) : 1;
      const box = document.getElementById('error_bars');
      if (!rows.length) {
        box.innerHTML = '<div class="hint">暂无错误类型</div>';
        return;
      }
      box.innerHTML = rows.map(([name, count]) => {
        const width = Math.max(3, Math.round((Number(count || 0) / max) * 100));
        return '<div class="error-row">' +
          '<div>' + name + '</div>' +
          '<div class="bar"><i style="width:' + width + '%"></i></div>' +
          '<div>' + fmt(count) + '</div>' +
        '</div>';
      }).join('');
    }

    async function refresh() {
      if (document.hidden) return;
      const windowMinutes = document.getElementById('window_minutes').value;
      const params = new URLSearchParams(window.location.search);
      const adminToken = params.get('admin_token');
      const statsUrl = new URL('/admin/stats', window.location.origin);
      statsUrl.searchParams.set('window', windowMinutes);
      if (adminToken) {
        statsUrl.searchParams.set('admin_token', adminToken);
      }

      const res = await fetch(statsUrl.toString(), { cache: 'no-store' });
      if (!res.ok) return;
      const data = await res.json();
      window.__series = data.series || [];
      const t = data.totals || {};
      const wt = data.window_totals || {};
      const series = window.__series || [];
      const by = wt.by_status || {};
      const byErr = wt.by_error_type || {};
      const byProvider = wt.by_provider || {};
      const byProviderFail = wt.by_provider_failure || {};
      const keyStats = data.key_stats || [];
      const cooldownEvents = data.cooldown_events || [];
      const byProviderFromKeys = {};
      const byProviderFailFromKeys = {};
      keyStats.forEach((k) => {
        const p = k.provider;
        if (!p) return;
        byProviderFromKeys[p] = Number(byProviderFromKeys[p] || 0) + Number(k.window_total || 0);
        // 用 key 维度 4xx 作为失败下限补齐，避免旧数据里 provider 维度为空时整表失真
        byProviderFailFromKeys[p] = Number(byProviderFailFromKeys[p] || 0) + Number(k.window_4xx || 0);
      });
      const mergedByProvider = Object.assign({}, byProvider);
      Object.keys(byProviderFromKeys).forEach((p) => {
        const cur = Number(mergedByProvider[p] || 0);
        const fromKeys = Number(byProviderFromKeys[p] || 0);
        if (fromKeys > cur) mergedByProvider[p] = fromKeys;
      });
      const mergedByProviderFail = Object.assign({}, byProviderFail);
      Object.keys(byProviderFailFromKeys).forEach((p) => {
        const cur = Number(mergedByProviderFail[p] || 0);
        const fromKeys = Number(byProviderFailFromKeys[p] || 0);
        if (fromKeys > cur) mergedByProviderFail[p] = fromKeys;
      });
      const peakMinute = series.reduce((m, x) => Math.max(m, Number(x.total || 0)), 0);
      const windowTotal = series.reduce((s, x) => s + Number(x.total || 0), 0);
      const windowFailure = series.reduce((s, x) => s + Number(x.failure || 0), 0);
      const windowSuccess = Math.max(windowTotal - windowFailure, 0);
      const windowSuccessRate = windowTotal > 0 ? ((windowSuccess / windowTotal) * 100) : 0;
      const providers = Object.keys(mergedByProvider || {});
      const activeCooldown = keyStats.filter((k) => Number(k.current_cooldown_ttl || 0) > 0).length;
      const failureRate = windowTotal > 0 ? ((windowFailure / windowTotal) * 100) : 0;

      document.getElementById('total').textContent = fmt(windowTotal);
      document.getElementById('success_rate').textContent = pct(windowSuccessRate);
      document.getElementById('failure').textContent = fmt(windowFailure);
      document.getElementById('latency').textContent = (wt.avg_latency_ms || 0) + ' ms';
      document.getElementById('providers').textContent = fmt(providers.length);
      document.getElementById('cooldown_keys').textContent = fmt(activeCooldown);
      document.getElementById('qps_hint').textContent = '峰值分钟调用: ' + fmt(peakMinute) + ' · 累计总调用: ' + fmt(t.total);
      document.getElementById('failure_rate_hint').textContent = '失败率 ' + pct(failureRate);
      document.getElementById('err_hint').textContent = '错误类型 ' + fmt(Object.keys(byErr).length) + ' 种';
      document.getElementById('providers_hint').textContent = '出现失败 ' + fmt(Object.keys(mergedByProviderFail).length) + ' 个';
      document.getElementById('series_hint').textContent = '采样点: ' + fmt(window.__series.length);
      document.getElementById('updated').textContent = '更新时间: ' + new Date().toLocaleString();
      renderStatus(by);
      renderErrors(byErr);

      const providerNameSet = {};
      Object.keys(t.by_provider || {}).forEach((name) => { providerNameSet[name] = true; });
      Object.keys(mergedByProvider || {}).forEach((name) => { providerNameSet[name] = true; });
      const rows = Object.keys(providerNameSet).map((name) => {
        const total = Number(mergedByProvider[name] || 0);
        const fail = Number(mergedByProviderFail[name] || 0);
        const rateNum = total > 0 ? ((fail / total) * 100) : 0;
        return { name, total, fail, rateNum };
      }).sort((a, b) => b.fail - a.fail || b.rateNum - a.rateNum || b.total - a.total).slice(0, 10);
      const providerWindowTotal = Object.values(mergedByProvider || {}).reduce((s, v) => s + Number(v || 0), 0);
      const unassignedWindowRequests = Math.max(windowTotal - providerWindowTotal, 0);
      document.getElementById('unassigned_requests').textContent = fmt(unassignedWindowRequests);

      const tbody = document.getElementById('provider_rows');
      const topTotal = rows.reduce((s, r) => s + r.total, 0) || 1;
      tbody.innerHTML = rows.map((r) => {
        const ratio = Math.round((r.total / topTotal) * 100);
        return '<tr>' +
          '<td>' + r.name + '</td>' +
          '<td>' + fmt(r.total) + '</td>' +
          '<td>' + fmt(r.fail) + '</td>' +
          '<td><span class="' + badgeClass(r.rateNum) + '">' + pct(r.rateNum) + '</span></td>' +
          '<td><div class="bar"><i style="width:' + ratio + '%"></i></div></td>' +
        '</tr>';
      }).join('');
      if (!rows.length) {
        tbody.innerHTML = '<tr><td colspan="5" class="hint">暂无 Provider 调用数据</td></tr>';
      }

      const keyRows = keyStats.map((k) => {
        const score = Number(k.window_429 || 0) * 5 + Number(k.window_cooldown_count || 0) * 3 + Number(k.window_4xx || 0);
        return {
          provider: k.provider,
          key_id: k.key_id,
          window_4xx: Number(k.window_4xx || 0),
          window_429: Number(k.window_429 || 0),
          window_cooldown_count: Number(k.window_cooldown_count || 0),
          score
        };
      }).sort((a, b) => b.score - a.score).slice(0, 30);

      const keyTbody = document.getElementById('key_rows');
      keyTbody.innerHTML = keyRows.map((k) => {
        const scoreClass = k.score >= 25 ? 'bad-bg' : (k.score >= 10 ? 'warn-bg' : 'ok-bg');
        return '<tr>' +
          '<td>' + k.provider + '</td>' +
          '<td>' + k.key_id + '</td>' +
          '<td>' + fmt(k.window_4xx) + '</td>' +
          '<td>' + fmt(k.window_429) + '</td>' +
          '<td>' + fmt(k.window_cooldown_count) + '</td>' +
          '<td><span class="rate-badge ' + scoreClass + '">' + fmt(k.score) + '</span></td>' +
        '</tr>';
      }).join('');
      if (!keyRows.length) {
        keyTbody.innerHTML = '<tr><td colspan="6" class="hint">暂无 Key 统计</td></tr>';
      }

      const cooldownBox = document.getElementById('cooldown_rows');
      cooldownBox.innerHTML = cooldownEvents.slice(0, 50).map((e) => {
        return '<div class="event-item">' +
          '<div>' +
            '<strong>' + (e.provider || '-') + '</strong> / ' + (e.key_id || '-') +
            '<div class="event-meta">' + (e.source || '-') + '</div>' +
          '</div>' +
          '<div style="text-align:right">' +
            '<div><span class="' + statusClass(e.status) + '">' + (e.status || '-') + '</span></div>' +
            '<div class="event-meta">' + fmt(e.ttl) + 's · ' + fmtTs(e.ts) + '</div>' +
          '</div>' +
        '</div>';
      }).join('');
      if (!cooldownEvents.length) {
        cooldownBox.innerHTML = '<div class="event-item"><span class="event-meta">暂无 Cooldown 事件</span></div>';
      }

      draw(window.__series);
    }

    (function syncTabLinks() {
      const params = new URLSearchParams(window.location.search);
      const adminToken = params.get('admin_token');
      if (!adminToken) return;
      document.getElementById('tab_overview').href = '/admin/dashboard?admin_token=' + encodeURIComponent(adminToken);
      document.getElementById('tab_topology').href = '/admin/dashboard/topology?admin_token=' + encodeURIComponent(adminToken);
      document.getElementById('tab_config').href = '/admin/dashboard/config?admin_token=' + encodeURIComponent(adminToken);
    })();

    window.addEventListener('resize', () => draw(window.__series || []));
    document.addEventListener('visibilitychange', refresh);
    document.getElementById('window_minutes').addEventListener('change', refresh);
    document.getElementById('btn_refresh').addEventListener('click', refresh);
    setInterval(refresh, 10000);
    refresh();
  </script>
</body>
</html>
]])
