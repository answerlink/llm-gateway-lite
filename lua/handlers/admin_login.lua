ngx.ctx.skip_stats = true
ngx.header['Content-Type'] = 'text/html; charset=utf-8'

ngx.say([[
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Admin 登录</title>
  <style>
    :root {
      --bg: #f3f6fc;
      --panel: #fff;
      --line: #d9e2f1;
      --text: #0f172a;
      --muted: #64748b;
      --brand: #2563eb;
      --shadow: 0 12px 28px rgba(15, 23, 42, 0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background:
        radial-gradient(1200px 500px at 0% 0%, #e7f0ff 0%, rgba(231,240,255,0) 60%),
        var(--bg);
      color: var(--text);
      font-family: Inter, "PingFang SC", "Hiragino Sans GB", sans-serif;
    }
    .card {
      width: min(420px, 92vw);
      border: 1px solid var(--line);
      border-radius: 16px;
      background: var(--panel);
      box-shadow: var(--shadow);
      padding: 18px;
    }
    h1 { margin: 0; font-size: 22px; font-weight: 800; }
    p { margin: 8px 0 14px; color: var(--muted); font-size: 13px; }
    input {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 10px 12px;
      font-size: 14px;
      margin-bottom: 10px;
    }
    button {
      width: 100%;
      border: 0;
      border-radius: 10px;
      padding: 10px 12px;
      background: var(--brand);
      color: #fff;
      font-size: 14px;
      cursor: pointer;
    }
    .hint { margin-top: 10px; font-size: 12px; color: var(--muted); }
  </style>
</head>
<body>
  <div class="card">
    <h1>管理后台登录</h1>
    <p>请输入 Admin Token 后进入看板。</p>
    <input id="token" type="password" placeholder="请输入 admin token" />
    <button id="go">进入管理页</button>
    <div class="hint">提示：Token 会拼接到 URL 参数中（admin_token）。</div>
  </div>
  <script>
    const params = new URLSearchParams(window.location.search);
    const next = params.get('next') || '/admin/dashboard';
    const input = document.getElementById('token');
    const btn = document.getElementById('go');

    function go() {
      const token = (input.value || '').trim();
      if (!token) return;
      let target;
      try {
        target = new URL(next, window.location.origin);
      } catch (_) {
        target = new URL('/admin/dashboard', window.location.origin);
      }
      target.searchParams.set('admin_token', token);
      window.location.href = target.toString();
    }

    btn.addEventListener('click', go);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') go();
    });
  </script>
</body>
</html>
]])
