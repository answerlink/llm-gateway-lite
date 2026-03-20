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
  <title>LLM Gateway 配置中心</title>
  <style>
    :root {
      --bg: #f3f6fc;
      --panel: #fff;
      --line: #d9e2f1;
      --text: #0f172a;
      --muted: #64748b;
      --brand: #2563eb;
      --ok: #059669;
      --bad: #dc2626;
      --shadow: 0 10px 24px rgba(15, 23, 42, 0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: radial-gradient(1200px 500px at 0% 0%, #e7f0ff 0%, rgba(231,240,255,0) 60%), var(--bg);
      color: var(--text);
      font-family: Inter, "PingFang SC", "Hiragino Sans GB", sans-serif;
    }
    .wrap { max-width: 1320px; margin: 0 auto; padding: 20px; }
    .head { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; margin-bottom: 12px; }
    h1 { margin: 0; font-size: 26px; font-weight: 800; }
    .sub { color: var(--muted); font-size: 13px; margin-top: 5px; }
    .tabs { display: inline-flex; border: 1px solid var(--line); border-radius: 999px; overflow: hidden; background: var(--panel); box-shadow: var(--shadow); }
    .tabs a { text-decoration: none; color: #334155; padding: 8px 15px; border-right: 1px solid var(--line); font-size: 13px; }
    .tabs a:last-child { border-right: 0; }
    .tabs .active { color: #fff; background: linear-gradient(135deg, #2e6ef7 0%, #2563eb 100%); font-weight: 600; }
    .toolbar {
      border: 1px solid var(--line);
      border-radius: 14px;
      background: var(--panel);
      padding: 12px;
      display: flex;
      gap: 10px;
      align-items: center;
      flex-wrap: wrap;
      box-shadow: var(--shadow);
      margin-bottom: 12px;
    }
    select, button {
      border: 1px solid var(--line);
      border-radius: 10px;
      background: #fff;
      padding: 7px 10px;
      font-size: 13px;
    }
    button { cursor: pointer; }
    button.primary { background: var(--brand); color: #fff; border-color: var(--brand); }
    button.warn { border-color: #fbbf24; color: #92400e; background: #fffbeb; }
    .status { margin-left: auto; font-size: 12px; color: var(--muted); }
    .grid { display: grid; grid-template-columns: 1fr 320px; gap: 12px; }
    .panel {
      border: 1px solid var(--line);
      border-radius: 14px;
      background: var(--panel);
      box-shadow: var(--shadow);
      padding: 12px;
    }
    textarea {
      width: 100%;
      min-height: 620px;
      resize: vertical;
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 10px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 12px;
      line-height: 1.5;
      background: #fbfdff;
    }
    .label { font-size: 12px; color: var(--muted); margin-bottom: 8px; }
    .list { max-height: 560px; overflow: auto; border: 1px solid var(--line); border-radius: 10px; }
    .item { padding: 8px 10px; border-bottom: 1px solid var(--line); cursor: pointer; font-size: 12px; }
    .item:last-child { border-bottom: 0; }
    .item.active { background: #eff6ff; color: #1d4ed8; font-weight: 600; }
    .kpi { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; margin-bottom: 10px; }
    .kpi .box { border: 1px solid var(--line); border-radius: 10px; background: #f8fbff; padding: 8px; }
    .k { font-size: 12px; color: var(--muted); }
    .v { font-size: 20px; font-weight: 800; margin-top: 6px; }
    .good { color: var(--ok); }
    .bad { color: var(--bad); }
    @media (max-width: 1080px) {
      .grid { grid-template-columns: 1fr; }
      textarea { min-height: 420px; }
      .status { width: 100%; margin-left: 0; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="head">
      <div>
        <h1>配置中心</h1>
        <div class="sub">可视化管理 <code>providers.yaml</code> 与 <code>models.yaml</code>，支持保存与历史版本回看（北京时间）</div>
      </div>
      <div class="tabs">
        <a href="/admin/dashboard" id="tab_overview">概览</a>
        <a href="/admin/dashboard/topology" id="tab_topology">模型与渠道</a>
        <a href="/admin/dashboard/config" class="active" id="tab_config">配置中心</a>
      </div>
    </div>

    <div class="kpi">
      <div class="box"><div class="k">模型数</div><div class="v" id="k_models">0</div></div>
      <div class="box"><div class="k">Provider 数</div><div class="v" id="k_providers">0</div></div>
    </div>

    <div class="toolbar">
      <label>配置文件</label>
      <select id="file_select">
        <option value="providers.yaml">providers.yaml</option>
        <option value="models.yaml">models.yaml</option>
      </select>
      <button type="button" id="btn_reload">加载当前</button>
      <button type="button" id="btn_apply_version" class="warn">加载历史到编辑器</button>
      <button type="button" id="btn_save" class="primary">保存并生效</button>
      <span class="status" id="status">状态: 初始化中...</span>
    </div>

    <div class="grid">
      <div class="panel">
        <div class="label">YAML 编辑器</div>
        <textarea id="editor" spellcheck="false"></textarea>
      </div>
      <div class="panel">
        <div class="label">历史版本（北京时间）</div>
        <div class="list" id="history_list"></div>
      </div>
    </div>
  </div>

  <script>
    const state = {
      selectedFile: 'providers.yaml',
      selectedVersion: '',
      adminToken: new URLSearchParams(window.location.search).get('admin_token'),
      editable: true,
    };

    function withToken(url) {
      if (state.adminToken) url.searchParams.set('admin_token', state.adminToken);
      return url;
    }

    function setStatus(text, cls) {
      const el = document.getElementById('status');
      el.textContent = text;
      el.className = 'status ' + (cls || '');
    }

    async function fetchJSON(url, init) {
      const res = await fetch(url, init || { cache: 'no-store' });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error((data.error && data.error.message) || 'request failed');
      }
      return data;
    }

    function updateTabs() {
      if (!state.adminToken) return;
      const t = encodeURIComponent(state.adminToken);
      document.getElementById('tab_overview').href = '/admin/dashboard?admin_token=' + t;
      document.getElementById('tab_topology').href = '/admin/dashboard/topology?admin_token=' + t;
      document.getElementById('tab_config').href = '/admin/dashboard/config?admin_token=' + t;
    }

    async function loadCatalogSummary() {
      const url = withToken(new URL('/admin/catalog', window.location.origin));
      const data = await fetchJSON(url.toString(), { cache: 'no-store' });
      document.getElementById('k_models').textContent = Number((data.summary || {}).models || 0).toLocaleString();
      document.getElementById('k_providers').textContent = Number((data.summary || {}).providers || 0).toLocaleString();
    }

    async function loadIndex() {
      const url = withToken(new URL('/admin/configs', window.location.origin));
      url.searchParams.set('action', 'index');
      const data = await fetchJSON(url.toString(), { cache: 'no-store' });
      state.editable = !!data.editable;
      const pick = state.selectedFile === 'models.yaml' ? data.files.models : data.files.providers;
      document.getElementById('editor').value = (pick && pick.content) || '';
      renderHistory((pick && pick.history) || []);
      setStatus(state.editable ? '状态: 可编辑' : '状态: 只读模式', state.editable ? 'good' : 'bad');
      document.getElementById('btn_save').disabled = !state.editable;
    }

    async function loadCurrent(fileName) {
      const url = withToken(new URL('/admin/configs', window.location.origin));
      url.searchParams.set('action', 'current');
      url.searchParams.set('file', fileName);
      const data = await fetchJSON(url.toString(), { cache: 'no-store' });
      document.getElementById('editor').value = data.content || '';
      setStatus('状态: 已加载当前 ' + fileName, 'good');
    }

    function renderHistory(versions) {
      const box = document.getElementById('history_list');
      if (!versions || !versions.length) {
        box.innerHTML = '<div class="item">暂无历史版本</div>';
        return;
      }
      box.innerHTML = versions.map((v) => {
        return '<div class="item" data-id="' + v.id + '">' + v.created_at_bj + '<br><span style="color:#64748b;">' + v.id + '</span></div>';
      }).join('');
      Array.from(box.querySelectorAll('.item')).forEach((el) => {
        el.addEventListener('click', () => {
          Array.from(box.querySelectorAll('.item')).forEach((x) => x.classList.remove('active'));
          el.classList.add('active');
          state.selectedVersion = el.getAttribute('data-id') || '';
          setStatus('状态: 已选中版本 ' + state.selectedVersion, '');
        });
      });
    }

    async function loadHistory(fileName) {
      const url = withToken(new URL('/admin/configs', window.location.origin));
      url.searchParams.set('action', 'history');
      url.searchParams.set('file', fileName);
      url.searchParams.set('limit', '80');
      const data = await fetchJSON(url.toString(), { cache: 'no-store' });
      renderHistory(data.versions || []);
    }

    async function loadSelectedVersionToEditor() {
      if (!state.selectedVersion) {
        setStatus('状态: 请先选择历史版本', 'bad');
        return;
      }
      const url = withToken(new URL('/admin/configs', window.location.origin));
      url.searchParams.set('action', 'version');
      url.searchParams.set('file', state.selectedFile);
      url.searchParams.set('version', state.selectedVersion);
      const data = await fetchJSON(url.toString(), { cache: 'no-store' });
      document.getElementById('editor').value = data.content || '';
      setStatus('状态: 已加载历史版本到编辑器（未保存）', 'warn');
    }

    async function saveCurrent() {
      if (!state.editable) {
        setStatus('状态: 当前为只读模式，禁止保存', 'bad');
        return;
      }
      const content = document.getElementById('editor').value;
      setStatus('状态: 保存中...', '');
      const url = withToken(new URL('/admin/configs', window.location.origin));
      const data = await fetchJSON(url.toString(), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'save',
          file: state.selectedFile,
          content: content,
          operator: 'admin-ui'
        }),
      });
      setStatus('状态: 保存成功，生效时间 ' + data.saved_at_bj, 'good');
      await Promise.all([loadHistory(state.selectedFile), loadCatalogSummary()]);
    }

    async function onFileChanged() {
      state.selectedFile = document.getElementById('file_select').value;
      state.selectedVersion = '';
      await Promise.all([loadCurrent(state.selectedFile), loadHistory(state.selectedFile)]);
    }

    document.getElementById('file_select').addEventListener('change', onFileChanged);
    document.getElementById('btn_reload').addEventListener('click', () => onFileChanged());
    document.getElementById('btn_apply_version').addEventListener('click', () => loadSelectedVersionToEditor());
    document.getElementById('btn_save').addEventListener('click', () => saveCurrent());

    updateTabs();
    Promise.all([loadCatalogSummary(), loadIndex()]).then(async () => {
      await onFileChanged();
    }).catch((e) => {
      setStatus('状态: 初始化失败 - ' + e.message, 'bad');
    });
  </script>
</body>
</html>
]])
