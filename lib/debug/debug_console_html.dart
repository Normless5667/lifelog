/// 内嵌于 App 内的单页深色电脑调试控制台 HTML（零外部资源依赖，局域网离线可用）。
const String kDebugConsoleHtml = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>LifeLog 电脑调试台</title>
<style>
  :root {
    --bg: #0d1117;
    --panel: #161b22;
    --panel-2: #1c222b;
    --border: #30363d;
    --text: #e6edf3;
    --muted: #8b949e;
    --accent: #58a6ff;
    --ok: #3fb950;
    --warn: #d29922;
    --err: #f85149;
    --err-bg: rgba(248, 81, 73, 0.14);
    --err-border: rgba(248, 81, 73, 0.45);
    --ai: #a371f7;
    --ocr: #39c5cf;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0; padding: 0; height: 100%;
    background: var(--bg); color: var(--text);
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Microsoft YaHei", monospace;
    font-size: 13px;
  }
  body { display: flex; flex-direction: column; overflow: hidden; }

  /* 顶部区域：状态 + Token + IP + 快捷操作 */
  header {
    background: var(--panel);
    border-bottom: 1px solid var(--border);
    padding: 10px 14px;
    display: flex; flex-wrap: wrap; align-items: center; gap: 10px;
  }
  .brand { font-weight: 700; font-size: 14px; display: flex; align-items: center; gap: 8px; }
  .dot {
    width: 10px; height: 10px; border-radius: 50%;
    background: var(--err); display: inline-block;
    box-shadow: 0 0 8px rgba(248,81,73,0.6);
  }
  .dot.ok { background: var(--ok); box-shadow: 0 0 8px rgba(63,185,80,0.6); }
  .dot.wait { background: var(--warn); box-shadow: 0 0 8px rgba(210,153,34,0.6); }
  .pill {
    background: var(--panel-2); border: 1px solid var(--border);
    border-radius: 999px; padding: 3px 10px; color: var(--muted); font-size: 12px;
  }
  .pill strong { color: var(--text); }
  .spacer { flex: 1; }
  input[type="text"], input[type="number"] {
    background: var(--bg); color: var(--text);
    border: 1px solid var(--border); border-radius: 6px;
    padding: 5px 9px; font-family: inherit; font-size: 12.5px; outline: none;
  }
  input:focus { border-color: var(--accent); }
  button {
    background: var(--panel-2); color: var(--text);
    border: 1px solid var(--border); border-radius: 6px;
    padding: 5px 11px; font-family: inherit; font-size: 12.5px;
    cursor: pointer; transition: background 0.15s, border-color 0.15s;
  }
  button:hover { background: #262e39; border-color: #48525e; }
  button.primary { background: #1f6feb; border-color: #388bfd; color: #fff; font-weight: 600; }
  button.primary:hover { background: #388bfd; }
  button.danger { color: var(--err); border-color: var(--err-border); }
  button.active { background: rgba(88,166,255,0.18); border-color: var(--accent); color: var(--accent); }

  /* 过滤工具条 */
  .toolbar {
    background: var(--panel-2); border-bottom: 1px solid var(--border);
    padding: 7px 14px; display: flex; flex-wrap: wrap; align-items: center; gap: 8px;
  }
  .chips { display: flex; gap: 6px; flex-wrap: wrap; }
  .chip { padding: 3px 9px; border-radius: 999px; font-size: 12px; }
  #searchInput { width: 200px; }
  label.chk { display: flex; align-items: center; gap: 5px; color: var(--muted); font-size: 12px; cursor: pointer; }
  #copyToast { color: var(--ok); font-size: 12px; min-width: 72px; text-align: right; }

  /* 中间区域：实时日志流 */
  main {
    flex: 1; overflow-y: auto; padding: 10px 14px;
    display: flex; flex-direction: column; gap: 6px;
  }
  .log-row {
    background: var(--panel); border: 1px solid var(--border);
    border-left: 3px solid var(--border); border-radius: 6px;
    padding: 7px 10px; line-height: 1.48; word-break: break-word;
  }
  .log-row.lvl-error {
    background: var(--err-bg); border-color: var(--err-border);
    border-left-color: var(--err);
  }
  .log-row.lvl-warn { border-left-color: var(--warn); }
  .log-row.lvl-info { border-left-color: var(--accent); }
  .log-row.tag-ai { border-left-color: var(--ai); }
  .log-row.tag-ocr { border-left-color: var(--ocr); }
  .log-meta {
    display: flex; align-items: center; gap: 8px; margin-bottom: 3px; font-size: 11.5px; color: var(--muted);
  }
  .badge {
    padding: 1px 6px; border-radius: 4px; font-weight: 700; font-size: 10.5px; text-transform: uppercase;
    background: rgba(139,148,158,0.18); color: var(--text);
  }
  .badge.error { background: var(--err); color: #fff; }
  .badge.warn { background: var(--warn); color: #000; }
  .badge.info { background: rgba(88,166,255,0.2); color: var(--accent); }
  .tag-pill { color: var(--accent); font-weight: 600; }
  .tag-pill.ai { color: var(--ai); }
  .tag-pill.ocr { color: var(--ocr); }
  .log-msg { white-space: pre-wrap; color: var(--text); }
  .log-row.lvl-error .log-msg { color: #ffdcd7; font-weight: 600; }
  .log-stack {
    margin-top: 6px; padding: 7px 9px; border-radius: 5px;
    background: rgba(0,0,0,0.42); color: #ffb4ab;
    font-size: 11.5px; white-space: pre-wrap; overflow-x: auto;
  }
  .empty-hint {
    margin: auto; color: var(--muted); text-align: center; padding: 36px 16px;
  }

  /* 底部区域：配置调参与实时预览 */
  footer {
    background: var(--panel); border-top: 1px solid var(--border);
    padding: 10px 14px; display: flex; flex-wrap: wrap; align-items: center; gap: 12px;
  }
  .cfg-group { display: flex; align-items: center; gap: 6px; }
  .cfg-group label { color: var(--muted); font-size: 12px; white-space: nowrap; }
  .cfg-group input { width: 122px; }
  .preview-box {
    flex: 1; min-width: 240px;
    background: var(--bg); border: 1px solid var(--border); border-radius: 6px;
    padding: 6px 10px; font-size: 12px; color: var(--muted);
    display: flex; flex-wrap: wrap; gap: 12px; align-items: center;
  }
  .preview-box strong { color: var(--ok); }
</style>
</head>
<body>
<header>
  <div class="brand">
    <span id="connDot" class="dot wait"></span>
    <span>LifeLog 调试台</span>
    <span id="connText" class="pill">连接中...</span>
  </div>
  <span class="pill">手机 IP: <strong id="phoneIp">--</strong></span>
  <span class="pill">版本: <strong id="appVer">--</strong></span>
  <span class="pill">日志: <strong id="logCount">0</strong></span>
  <div class="spacer"></div>
  <input id="tokenInput" type="text" placeholder="访问 Token" style="width: 170px;" />
  <button id="reconnectBtn" class="primary">重连</button>
</header>

<div class="toolbar">
  <div class="chips" id="filterChips">
    <button class="chip active" data-filter="all">全部</button>
    <button class="chip" data-filter="error">仅异常</button>
    <button class="chip" data-filter="ocr">OCR</button>
    <button class="chip" data-filter="ai">AI</button>
    <button class="chip" data-filter="telemetry">页面/功能</button>
  </div>
  <input id="searchInput" type="text" placeholder="搜索日志关键字..." />
  <label class="chk"><input id="autoScrollChk" type="checkbox" checked /> 自动滚到底部</label>
  <div class="spacer"></div>
  <span id="copyToast"></span>
  <button id="copyAllBtn" class="primary">一键复制全部日志</button>
  <button id="clearBtn" class="danger">清空</button>
</div>

<main id="logContainer">
  <div class="empty-hint" id="emptyHint">等待手机端推送日志… 在手机上操作页面或点击「拍高清帧」即可实时看到完整堆栈</div>
</main>

<footer>
  <div class="cfg-group">
    <label for="fxInput">汇率 (1 VND → RMB)</label>
    <input id="fxInput" type="number" step="0.000001" value="0.000285" />
  </div>
  <div class="cfg-group">
    <label for="thInput">置信度阈值</label>
    <input id="thInput" type="number" step="0.05" min="0" max="1" value="0.6" />
  </div>
  <button id="applyCfgBtn" class="primary">下发配置（即时生效）</button>
  <div class="preview-box" id="cfgPreview">
    <span>实时预览: <strong id="previewText">100,000₫ ≈ ¥28.5 · threshold=0.60</strong></span>
    <span id="syncStatus">尚未同步</span>
  </div>
</footer>

<script>
(() => {
  const qs = new URLSearchParams(location.search);
  const tokenInput = document.getElementById('tokenInput');
  const connDot = document.getElementById('connDot');
  const connText = document.getElementById('connText');
  const phoneIpEl = document.getElementById('phoneIp');
  const appVerEl = document.getElementById('appVer');
  const logCountEl = document.getElementById('logCount');
  const logContainer = document.getElementById('logContainer');
  const emptyHint = document.getElementById('emptyHint');
  const searchInput = document.getElementById('searchInput');
  const autoScrollChk = document.getElementById('autoScrollChk');
  const copyToast = document.getElementById('copyToast');
  const fxInput = document.getElementById('fxInput');
  const thInput = document.getElementById('thInput');
  const previewText = document.getElementById('previewText');
  const syncStatus = document.getElementById('syncStatus');

  tokenInput.value = qs.get('token') || '';
  phoneIpEl.textContent = location.host;

  let ws = null;
  let reconnectTimer = null;
  let activeFilter = 'all';
  const logs = [];

  function setConnState(state, text) {
    connDot.className = 'dot ' + (state === 'ok' ? 'ok' : state === 'wait' ? 'wait' : '');
    connText.textContent = text;
  }

  function updatePreview() {
    const fx = parseFloat(fxInput.value);
    const th = parseFloat(thInput.value);
    const rmb = Number.isFinite(fx) && fx > 0 ? (100000 * fx).toFixed(2) : '--';
    const thStr = Number.isFinite(th) ? th.toFixed(2) : '--';
    previewText.textContent = `100,000₫ ≈ ¥${rmb} · threshold=${thStr}`;
  }

  function matchFilter(entry) {
    const lvl = (entry.level || 'info').toLowerCase();
    const tag = (entry.tag || '').toLowerCase();
    if (activeFilter === 'error' && lvl !== 'error') return false;
    if (activeFilter === 'ocr' && !tag.includes('ocr') && !(entry.message || '').toLowerCase().includes('ocr') && !(entry.message || '').toLowerCase().includes('mlkit') && !(entry.message || '').toLowerCase().includes('inputimage')) return false;
    if (activeFilter === 'ai' && !tag.includes('ai')) return false;
    if (activeFilter === 'telemetry' && !tag.includes('page') && !tag.includes('feature')) return false;
    const kw = searchInput.value.trim().toLowerCase();
    if (kw) {
      const hay = `${entry.ts || ''} ${entry.level || ''} ${entry.tag || ''} ${entry.message || ''} ${entry.stack || ''}`.toLowerCase();
      if (!hay.includes(kw)) return false;
    }
    return true;
  }

  function createLogEl(entry) {
    const lvl = (entry.level || 'info').toLowerCase();
    const tag = (entry.tag || 'app');
    const tagLower = tag.toLowerCase();
    const row = document.createElement('div');
    let cls = `log-row lvl-${lvl}`;
    if (tagLower.includes('ai')) cls += ' tag-ai';
    else if (tagLower.includes('ocr')) cls += ' tag-ocr';
    row.className = cls;

    const meta = document.createElement('div');
    meta.className = 'log-meta';
    const tsSpan = document.createElement('span');
    tsSpan.textContent = entry.ts || '';
    const lvlBadge = document.createElement('span');
    lvlBadge.className = `badge ${lvl}`;
    lvlBadge.textContent = lvl;
    const tagSpan = document.createElement('span');
    tagSpan.className = 'tag-pill' + (tagLower.includes('ai') ? ' ai' : tagLower.includes('ocr') ? ' ocr' : '');
    tagSpan.textContent = `[${tag}]`;
    meta.append(tsSpan, lvlBadge, tagSpan);

    const msgDiv = document.createElement('div');
    msgDiv.className = 'log-msg';
    msgDiv.textContent = entry.message || '';
    row.append(meta, msgDiv);

    if (entry.stack) {
      const st = document.createElement('div');
      st.className = 'log-stack';
      st.textContent = entry.stack;
      row.append(st);
    }
    return row;
  }

  function renderAll() {
    logContainer.innerHTML = '';
    const matched = logs.filter(matchFilter);
    logCountEl.textContent = String(logs.length);
    if (matched.length === 0) {
      logContainer.appendChild(emptyHint);
      return;
    }
    const frag = document.createDocumentFragment();
    for (const e of matched) frag.appendChild(createLogEl(e));
    logContainer.appendChild(frag);
    if (autoScrollChk.checked) {
      logContainer.scrollTop = logContainer.scrollHeight;
    }
  }

  function appendLog(entry) {
    logs.push(entry);
    if (logs.length > 2000) logs.shift();
    logCountEl.textContent = String(logs.length);
    if (!matchFilter(entry)) return;
    if (emptyHint.parentNode === logContainer) logContainer.removeChild(emptyHint);
    logContainer.appendChild(createLogEl(entry));
    if (autoScrollChk.checked) {
      logContainer.scrollTop = logContainer.scrollHeight;
    }
  }

  function formatLogsAsText() {
    const matched = logs.filter(matchFilter);
    return matched.map(e => {
      const head = `${e.ts || ''} [${(e.level || 'info').toUpperCase()}] [${e.tag || 'app'}] ${e.message || ''}`;
      return e.stack ? `${head}\n${e.stack}` : head;
    }).join('\n----------------------------------------\n');
  }

  async function copyTextSafe(text) {
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (_) {}
    }
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.top = '-9999px';
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (_) {}
    document.body.removeChild(ta);
    return ok;
  }

  function connect() {
    if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
    if (ws) { try { ws.close(); } catch (_) {} ws = null; }
    const token = tokenInput.value.trim();
    if (!token) {
      setConnState('err', '缺少 Token');
      return;
    }
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${proto}//${location.host}/ws?token=${encodeURIComponent(token)}`;
    setConnState('wait', '连接中...');
    try {
      ws = new WebSocket(url);
    } catch (err) {
      setConnState('err', '连接异常');
      return;
    }
    ws.onopen = () => {
      setConnState('ok', '已连接');
    };
    ws.onmessage = (ev) => {
      let data;
      try { data = JSON.parse(ev.data); } catch (_) { return; }
      if (data.type === 'hello') {
        if (data.ip && data.port) phoneIpEl.textContent = `${data.ip}:${data.port}`;
        if (data.version) appVerEl.textContent = data.version;
        if (typeof data.fx_rate === 'number') fxInput.value = String(data.fx_rate);
        if (typeof data.threshold === 'number') thInput.value = String(data.threshold);
        updatePreview();
        syncStatus.textContent = `手机已同步 (${new Date().toLocaleTimeString()})`;
        logs.length = 0;
        if (Array.isArray(data.history)) {
          for (const item of data.history) logs.push(item);
        }
        renderAll();
      } else if (data.type === 'log') {
        appendLog(data);
      } else if (data.type === 'config') {
        if (typeof data.fx_rate === 'number') fxInput.value = String(data.fx_rate);
        if (typeof data.threshold === 'number') thInput.value = String(data.threshold);
        updatePreview();
        syncStatus.textContent = `配置已生效 (${new Date().toLocaleTimeString()})`;
      } else if (data.type === 'cleared') {
        logs.length = 0;
        renderAll();
      }
    };
    ws.onclose = () => {
      setConnState('err', '已断开，3秒后重连');
      reconnectTimer = setTimeout(connect, 3000);
    };
    ws.onerror = () => {
      setConnState('err', '连接失败（检查 Token / Wi-Fi）');
    };
  }

  document.getElementById('reconnectBtn').addEventListener('click', connect);
  document.getElementById('filterChips').addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-filter]');
    if (!btn) return;
    activeFilter = btn.dataset.filter;
    for (const b of document.querySelectorAll('#filterChips button')) {
      b.classList.toggle('active', b === btn);
    }
    renderAll();
  });
  searchInput.addEventListener('input', renderAll);
  fxInput.addEventListener('input', updatePreview);
  thInput.addEventListener('input', updatePreview);

  document.getElementById('applyCfgBtn').addEventListener('click', () => {
    const fx = parseFloat(fxInput.value);
    const th = parseFloat(thInput.value);
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      syncStatus.textContent = '未连接手机，无法下发';
      return;
    }
    const payload = { cmd: 'update_config' };
    if (Number.isFinite(fx) && fx > 0) payload.fx_rate = fx;
    if (Number.isFinite(th) && th >= 0 && th <= 1) payload.threshold = th;
    ws.send(JSON.stringify(payload));
    syncStatus.textContent = '已下发，等待手机确认...';
  });

  document.getElementById('copyAllBtn').addEventListener('click', async () => {
    const txt = formatLogsAsText();
    if (!txt) {
      copyToast.textContent = '暂无日志';
      return;
    }
    const ok = await copyTextSafe(txt);
    copyToast.textContent = ok ? `已复制 ${logs.filter(matchFilter).length} 条` : '复制失败';
    setTimeout(() => { copyToast.textContent = ''; }, 2500);
  });

  document.getElementById('clearBtn').addEventListener('click', () => {
    logs.length = 0;
    renderAll();
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ cmd: 'clear_logs' }));
    }
  });

  updatePreview();
  connect();
})();
</script>
</body>
</html>
''';
