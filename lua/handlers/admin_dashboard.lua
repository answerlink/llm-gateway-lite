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
  <title>LLM Gateway Dashboard</title>
  <style>
    :root {
      --bg: #f6f8fb;
      --card: #ffffff;
      --text: #1f2937;
      --muted: #6b7280;
      --ok: #10b981;
      --bad: #ef4444;
      --line: #2563eb;
      --border: #e5e7eb;
    }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: "Segoe UI", "PingFang SC", "Hiragino Sans GB", sans-serif;
    }
    .wrap {
      max-width: 1100px;
      margin: 0 auto;
      padding: 20px;
    }
    .title {
      font-size: 24px;
      font-weight: 700;
      margin-bottom: 8px;
    }
    .sub {
      color: var(--muted);
      margin-bottom: 16px;
    }
    .head {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 10px;
      flex-wrap: wrap;
    }
    .tabs {
      display: inline-flex;
      border: 1px solid var(--border);
      border-radius: 999px;
      overflow: hidden;
      background: #fff;
    }
    .tabs a {
      text-decoration: none;
      color: #334155;
      padding: 7px 14px;
      font-size: 13px;
      border-right: 1px solid var(--border);
    }
    .tabs a:last-child { border-right: 0; }
    .tabs a.active {
      background: #2563eb;
      color: #fff;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
      margin-bottom: 12px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 12px;
      box-sizing: border-box;
    }
    .k {
      color: var(--muted);
      font-size: 13px;
    }
    .v {
      font-size: 24px;
      font-weight: 700;
      margin-top: 4px;
    }
    .ok { color: var(--ok); }
    .bad { color: var(--bad); }
    .chart {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 12px;
      margin-top: 12px;
    }
    canvas {
      width: 100%;
      height: 260px;
      display: block;
      margin-top: 10px;
    }
    .footer {
      margin-top: 10px;
      color: var(--muted);
      font-size: 12px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 8px;
      font-size: 13px;
    }
    th, td {
      border-bottom: 1px solid var(--border);
      text-align: left;
      padding: 6px 4px;
    }
    th {
      color: var(--muted);
      font-weight: 600;
    }
    .pill {
      display: inline-block;
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 2px 10px;
      background: #fff;
      margin-right: 8px;
    }
    @media (max-width: 900px) {
      .grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
    @media (max-width: 560px) {
      .grid {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="head">
      <div>
        <div class="title">LLM Gateway 调用统计</div>
        <div class="sub">
          <span class="pill">窗口: 最近 60 分钟</span>
          <span id="updated">更新时间: --</span>
        </div>
      </div>
      <div class="tabs">
        <a href="/admin/dashboard" class="active" id="tab_overview">概览</a>
        <a href="/admin/dashboard/topology" id="tab_topology">模型与渠道</a>
      </div>
    </div>
    <div class="grid">
      <div class="card"><div class="k">总调用</div><div id="total" class="v">0</div></div>
      <div class="card"><div class="k">成功率</div><div id="success_rate" class="v ok">0%</div></div>
      <div class="card"><div class="k">失败数</div><div id="failure" class="v bad">0</div></div>
      <div class="card"><div class="k">平均延迟</div><div id="latency" class="v">0 ms</div></div>
    </div>
    <div class="chart">
      <div class="k">每分钟调用量（蓝）/ 失败量（红）</div>
      <canvas id="calls"></canvas>
    </div>
    <div class="chart">
      <div class="k">状态分布</div>
      <div id="status_line" class="footer"></div>
    </div>
    <div class="chart">
      <div class="k">错误类型明细</div>
      <div id="error_line" class="footer"></div>
    </div>
    <div class="chart">
      <div class="k">Provider 失败榜</div>
      <table>
        <thead>
          <tr><th>Provider</th><th>总调用</th><th>失败</th><th>失败率</th></tr>
        </thead>
        <tbody id="provider_rows"></tbody>
      </table>
    </div>
    <div class="chart">
      <div class="k">Key 健康榜（最近窗口）</div>
      <table>
        <thead>
          <tr><th>Provider</th><th>Key</th><th>窗口4xx</th><th>窗口429</th><th>窗口Cooldown</th><th>当前Cooldown</th><th>最近4xx</th></tr>
        </thead>
        <tbody id="key_rows"></tbody>
      </table>
    </div>
    <div class="chart">
      <div class="k">Cooldown 事件流（最近 200 条）</div>
      <table>
        <thead>
          <tr><th>时间</th><th>Provider</th><th>Key</th><th>Status</th><th>TTL</th><th>来源</th></tr>
        </thead>
        <tbody id="cooldown_rows"></tbody>
      </table>
    </div>
    <div class="footer">数据来源: /admin/stats（内存统计，网关重启后清零）</div>
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

      ctx.strokeStyle = '#e5e7eb';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(pad, pad);
      ctx.lineTo(pad, pad + ch);
      ctx.lineTo(pad + cw, pad + ch);
      ctx.stroke();

      ctx.strokeStyle = '#2563eb';
      ctx.lineWidth = 2;
      ctx.beginPath();
      for (let i = 0; i < series.length; i++) {
        const p = series[i];
        const px = x(i);
        const py = y(p.total || 0);
        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      }
      ctx.stroke();

      ctx.strokeStyle = '#ef4444';
      ctx.lineWidth = 2;
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

    function fmtTs(ts) {
      const n = Number(ts || 0);
      if (!n) return '-';
      return new Date(n * 1000).toLocaleString();
    }

    async function refresh() {
      if (document.hidden) return;
      const params = new URLSearchParams(window.location.search);
      const adminToken = params.get('admin_token');
      const statsUrl = new URL('/admin/stats', window.location.origin);
      statsUrl.searchParams.set('window', '60');
      if (adminToken) {
        statsUrl.searchParams.set('admin_token', adminToken);
      }

      const res = await fetch(statsUrl.toString(), { cache: 'no-store' });
      if (!res.ok) return;
      const data = await res.json();
      window.__series = data.series || [];
      const t = data.totals || {};
      const by = t.by_status || {};
      const byErr = t.by_error_type || {};
      const byProvider = t.by_provider || {};
      const byProviderFail = t.by_provider_failure || {};
      const keyStats = data.key_stats || [];
      const cooldownEvents = data.cooldown_events || [];
      document.getElementById('total').textContent = fmt(t.total);
      document.getElementById('success_rate').textContent = (data.success_rate || 0) + '%';
      document.getElementById('failure').textContent = fmt(t.failure);
      document.getElementById('latency').textContent = (t.avg_latency_ms || 0) + ' ms';
      document.getElementById('updated').textContent = '更新时间: ' + new Date().toLocaleString();
      document.getElementById('status_line').textContent =
        '2xx: ' + fmt(by['2xx']) + ' | 3xx: ' + fmt(by['3xx']) + ' | 4xx: ' + fmt(by['4xx']) + ' | 5xx: ' + fmt(by['5xx']);
      const errParts = Object.entries(byErr)
        .sort((a, b) => (b[1] || 0) - (a[1] || 0))
        .map(([k, v]) => k + ': ' + fmt(v));
      document.getElementById('error_line').textContent = errParts.length ? errParts.join(' | ') : '暂无错误';

      const rows = Object.keys(byProvider).map((name) => {
        const total = Number(byProvider[name] || 0);
        const fail = Number(byProviderFail[name] || 0);
        const rate = total > 0 ? ((fail / total) * 100).toFixed(2) + '%' : '0%';
        return { name, total, fail, rateNum: total > 0 ? (fail / total) : 0, rate };
      }).sort((a, b) => b.fail - a.fail || b.rateNum - a.rateNum || b.total - a.total).slice(0, 10);

      const tbody = document.getElementById('provider_rows');
      tbody.innerHTML = rows.map((r) =>
        '<tr><td>' + r.name + '</td><td>' + fmt(r.total) + '</td><td>' + fmt(r.fail) + '</td><td>' + r.rate + '</td></tr>'
      ).join('');

      const keyRows = keyStats.slice(0, 30);
      const keyTbody = document.getElementById('key_rows');
      keyTbody.innerHTML = keyRows.map((k) => {
        return '<tr>' +
          '<td>' + k.provider + '</td>' +
          '<td>' + k.key_id + '</td>' +
          '<td>' + fmt(k.window_4xx) + '</td>' +
          '<td>' + fmt(k.window_429) + '</td>' +
          '<td>' + fmt(k.window_cooldown_count) + '</td>' +
          '<td>' + (k.current_cooldown_ttl > 0 ? (fmt(k.current_cooldown_ttl) + 's') : '-') + '</td>' +
          '<td>' + (k.last_4xx_ts ? (fmtTs(k.last_4xx_ts) + ' (' + (k.last_4xx_status || '-') + ')') : '-') + '</td>' +
        '</tr>';
      }).join('');
      if (!keyRows.length) {
        keyTbody.innerHTML = '<tr><td colspan="7">暂无 Key 统计</td></tr>';
      }

      const cooldownTbody = document.getElementById('cooldown_rows');
      cooldownTbody.innerHTML = cooldownEvents.slice(0, 50).map((e) => {
        return '<tr>' +
          '<td>' + fmtTs(e.ts) + '</td>' +
          '<td>' + (e.provider || '-') + '</td>' +
          '<td>' + (e.key_id || '-') + '</td>' +
          '<td>' + (e.status || '-') + '</td>' +
          '<td>' + fmt(e.ttl) + 's</td>' +
          '<td>' + (e.source || '-') + '</td>' +
        '</tr>';
      }).join('');
      if (!cooldownEvents.length) {
        cooldownTbody.innerHTML = '<tr><td colspan="6">暂无 Cooldown 事件</td></tr>';
      }

      draw(window.__series);
    }

    (function syncTabLinks() {
      const params = new URLSearchParams(window.location.search);
      const adminToken = params.get('admin_token');
      if (!adminToken) return;
      document.getElementById('tab_overview').href = '/admin/dashboard?admin_token=' + encodeURIComponent(adminToken);
      document.getElementById('tab_topology').href = '/admin/dashboard/topology?admin_token=' + encodeURIComponent(adminToken);
    })();

    window.addEventListener('resize', () => draw(window.__series || []));
    document.addEventListener('visibilitychange', refresh);
    setInterval(refresh, 10000);
    refresh();
  </script>
</body>
</html>
]])
