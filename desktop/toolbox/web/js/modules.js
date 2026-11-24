window.DNSModule = {
  lastAnswers: [],

  readForm() {
    const domain = document.getElementById('dns-domain').value.trim();
    const server = document.getElementById('dns-server').value.trim() || '127.0.0.1';
    const port = parseInt(document.getElementById('dns-port').value, 10) || 53;
    const qtype = document.getElementById('dns-qtype').value;
    const tcp = document.getElementById('dns-tcp').checked;
    if (!domain) {
      App.toast('请输入目标域名', 'warn');
      return null;
    }
    return { domain, server, port, qtype, tcp };
  },

  async query() {
    const form = this.readForm();
    if (!form) return;

    App.setBusy(true, '正在发送 DNS 查询...');
    try {
      const res = await window.pywebview.api.dns_query(
        form.domain, form.server, form.port, form.qtype, form.tcp,
      );
      this.renderQueryResult(res);
      if (!res.success) {
        const message = res.error || '未知错误';
        App.log('error', `DNS 查询失败: ${message}`);
        App.toast(`DNS 查询失败: ${message}`, 'error');
      }
    } catch (e) {
      App.log('error', `DNS 查询异常: ${e}`);
      App.toast(`DNS 查询异常: ${e}`, 'error');
    } finally {
      App.setBusy(false);
    }
  },

  async benchmark() {
    const form = this.readForm();
    if (!form) return;

    App.setBusy(true, '正在进行批量 DNS 压测...');
    document.getElementById('dns-result-container').style.display = 'block';
    document.getElementById('dns-answers-card').style.display = 'none';
    document.getElementById('dns-error-note').style.display = 'none';

    try {
      const res = await window.pywebview.api.dns_benchmark(
        form.domain, form.server, form.port, form.qtype, 5, form.tcp,
      );
      if (!res.started) {
        App.setBusy(false);
        App.toast(res.message || '压测未能启动', 'warn');
      }
    } catch (e) {
      App.setBusy(false);
      App.log('error', `DNS 压测异常: ${e}`);
      App.toast(`DNS 压测异常: ${e}`, 'error');
    }
  },

  setPreset(server) {
    const sInput = document.getElementById('dns-server');
    if (sInput) sInput.value = server;
    const pInput = document.getElementById('dns-port');
    if (pInput) pInput.value = '53';
    App.toast(`已应用 DNS 服务器: ${server}`, 'ok');
  },

  copyAnswers() {
    if (!this.lastAnswers || this.lastAnswers.length === 0) {
      return App.toast('当前没有可复制的解析记录', 'warn');
    }
    const lines = this.lastAnswers.map(a => `${a.name}\t${a.type}\t${a.ttl}s\t${a.value}`);
    navigator.clipboard.writeText(lines.join('\n')).then(() => {
      App.toast('解析结果已成功复制到剪贴板', 'ok');
    });
  },

  renderQueryResult(res) {
    const container = document.getElementById('dns-result-container');
    container.style.display = 'block';

    const errorNote = document.getElementById('dns-error-note');
    if (res.success) {
      errorNote.style.display = 'none';
      errorNote.textContent = '';
    } else {
      errorNote.style.display = 'block';
      errorNote.textContent = `查询失败：${res.error || '未知错误'}`;
    }

    const isOk = res.success && res.rcode === 'NOERROR';
    UI.stats(document.getElementById('dns-stats-grid'), [
      { label: '响应状态', value: res.rcode || (res.success ? 'NOERROR' : 'FAIL'), fail: !isOk },
      { label: '查询耗时', value: `${res.elapsed_ms || 0} ms` },
      { label: '传输协议', value: res.proto || (document.getElementById('dns-tcp').checked ? 'TCP' : 'UDP') },
      { label: '记录数量', value: `${res.answers ? res.answers.length : 0} 条` },
    ]);

    const answersCard = document.getElementById('dns-answers-card');
    const tbody = document.querySelector('#dns-table tbody');
    UI.clear(tbody);
    this.lastAnswers = res.answers || [];

    if (this.lastAnswers.length === 0) {
      answersCard.style.display = 'none';
      return;
    }

    answersCard.style.display = 'block';
    this.lastAnswers.forEach((answer) => {
      UI.row(tbody, [
        answer.name,
        { node: UI.badge(answer.type) },
        `${answer.ttl}s`,
        { node: UI.el('span', { className: 'mono', text: answer.value }) },
      ]);
    });
  },

  onBenchmarkDone(payload) {
    App.setBusy(false);
    if (!payload || !payload.success || !payload.data) {
      const message = payload && payload.message ? payload.message : '压测未完成';
      App.toast(message, payload && payload.message === '用户已取消压测' ? 'warn' : 'error');
      return;
    }

    const d = payload.data;
    const completed = d.completed || d.count;
    UI.stats(document.getElementById('dns-stats-grid'), [
      { label: '响应次数', value: `${d.success_count}/${completed}`, fail: d.loss_rate > 0 },
      { label: '丢包率', value: `${d.loss_rate}%`, fail: d.loss_rate > 0 },
      { label: '平均延迟', value: `${d.avg_ms} ms` },
      { label: '极值 (Min/Max)', value: `${d.min_ms} / ${d.max_ms} ms` },
    ]);

    const rcodes = d.rcodes || {};
    const rcodeText = Object.entries(rcodes).map(([k, v]) => `${k}×${v}`).join('，');
    App.log('info', `压测完成：完成 ${completed}/${d.count} 次${rcodeText ? `，响应状态 ${rcodeText}` : ''}`);
  },
};

window.ScannerModule = {
  currentFiles: [],
  filterMode: 'all',

  async startScan() {
    const dir = document.getElementById('scan-dir').value.trim();
    const exts = document.getElementById('scan-exts').value.trim() || '.dart,.go,.py';
    const threshold = parseInt(document.getElementById('scan-threshold').value, 10) || 600;
    const showAll = document.getElementById('scan-all').checked;
    const ignoreGenerated = !document.getElementById('scan-generated').checked;

    App.setBusy(true, '正在扫描项目源文件规模...');
    try {
      const res = await window.pywebview.api.scan_files(
        dir, exts, threshold, showAll, 'lines', ignoreGenerated,
      );
      if (!res.started) {
        App.setBusy(false);
        App.toast(res.message || '扫描未能启动', 'warn');
      }
    } catch (e) {
      App.setBusy(false);
      App.log('error', `代码扫描异常: ${e}`);
      App.toast(`代码扫描异常: ${e}`, 'error');
    }
  },

  setFilter(mode) {
    this.filterMode = mode;
    document.getElementById('btn-filter-all').classList.toggle('active', mode === 'all');
    document.getElementById('btn-filter-exceeded').classList.toggle('active', mode === 'exceeded');
    this.renderTable();
  },

  renderTable() {
    const tbody = document.querySelector('#scan-table tbody');
    UI.clear(tbody);
    const filesToDisplay = this.filterMode === 'exceeded'
      ? this.currentFiles.filter(item => item.exceeded)
      : this.currentFiles;

    document.getElementById('scan-matched-count').textContent = filesToDisplay.length;

    filesToDisplay.forEach((item, idx) => {
      const pathCell = UI.el('span', { className: 'mono' },
        item.rel_path,
        item.exceeded ? UI.el('strong', { className: 'is-fail tag-exceeded', text: ' [超标]' }) : null,
      );
      UI.row(tbody, [
        idx + 1,
        { className: item.exceeded ? 'is-fail' : '', node: UI.el('strong', { text: `${item.line_count} 行` }) },
        { node: UI.badge(item.ext.replace('.', '').toUpperCase(), item.ext === '.dart' ? 'badge' : 'badge-warn') },
        { node: pathCell },
        {
          node: UI.button('打开', () => {
            window.pywebview.api.open_explorer(item.full_path);
          }),
        },
      ]);
    });
  },

  onScanDone(payload) {
    App.setBusy(false);
    if (!payload || !payload.success || !payload.data) {
      const message = payload && payload.message ? payload.message : '扫描失败';
      App.toast(message, 'error');
      App.log('error', `代码扫描失败: ${message}`);
      return;
    }

    const d = payload.data;
    document.getElementById('scan-result-container').style.display = 'block';

    UI.stats(document.getElementById('scan-stats-grid'), [
      { label: '扫描文件总数', value: d.stats.total_scanned },
      { label: '代码总行数', value: d.stats.total_lines.toLocaleString() },
      { label: `超标文件 (>${d.threshold}行)`, value: d.exceeded_count, fail: d.exceeded_count > 0 },
      { label: '最大单个文件行数', value: d.max_file ? d.max_file.line_count : 0 },
    ]);

    this.currentFiles = d.matched_files || [];
    this.renderTable();
  },
};

window.LogoModule = {
  async refreshPreview() {
    try {
      const res = await window.pywebview.api.logo_preview();
      if (!res.success) {
        App.log('error', `Logo 预览失败: ${res.error || '未知错误'}`);
        return;
      }
      const palettes = res.palettes || {};
      const light = palettes.light || {};
      const dark = palettes.dark || {};

      document.getElementById('logo-preview-light').innerHTML = light.svg || '';
      document.getElementById('logo-preview-dark').innerHTML = dark.svg || '';
      document.getElementById('light-bg-hex').textContent = light.background || '—';
      document.getElementById('light-fg-hex').textContent = light.foreground || '—';
      document.getElementById('dark-bg-hex').textContent = dark.background || '—';
      document.getElementById('dark-fg-hex').textContent = dark.foreground || '—';
      document.getElementById('light-bg-swatch').style.background = light.background || 'transparent';
      document.getElementById('light-fg-swatch').style.background = light.foreground || 'transparent';
      document.getElementById('dark-bg-swatch').style.background = dark.background || 'transparent';
      document.getElementById('dark-fg-swatch').style.background = dark.foreground || 'transparent';
    } catch (e) {
      App.log('error', `Logo 预览异常: ${e}`);
    }
  },

  async exportAssets() {
    App.setBusy(true, '正在生成各尺寸 PNG 与 ICO 图标...');
    try {
      const res = await window.pywebview.api.logo_export();
      if (!res.started) {
        App.setBusy(false);
        App.toast(res.message || '导出未能启动', 'warn');
      }
    } catch (e) {
      App.setBusy(false);
      App.log('error', `Logo 导出异常: ${e}`);
      App.toast(`Logo 导出异常: ${e}`, 'error');
    }
  },

  onExportDone(payload) {
    App.setBusy(false);
    if (payload && payload.success) {
      App.toast('品牌资源导出成功，SVG、PNG 与 Windows ICO 已就绪', 'ok');
      App.log('info', `Logo 导出完成，耗时 ${payload.elapsed || 0}s`);
    } else {
      App.toast((payload && payload.message) || 'Logo 导出失败', 'error');
    }
  },
};

const VERSION_ANDROID_GROUPS = ['android'];

function renderVersionRows(tbody, items) {
  UI.clear(tbody);
  items.forEach((item) => {
    const isSource = item.kind === 'source';
    UI.row(tbody, [
      {
        node: UI.el('span', {},
          UI.el('strong', { text: item.name }),
          ' ',
          UI.badge(isSource ? '真源' : '派生', isSource ? 'badge' : 'badge badge-warn'),
        ),
      },
      {
        node: item.hardcoded
          ? UI.el('span', {},
              UI.badge(item.version || '—'),
              ' ',
              UI.badge(`硬编码 ${item.hardcoded}`, 'badge badge-fail'),
            )
          : UI.badge(item.version || '—'),
      },
      { node: UI.el('span', { className: 'text-muted', text: item.note || '' }) },
      { node: UI.el('span', { className: 'mono', text: item.rel_path }) },
    ]);
  });
}

function pickSourceVersion(items) {
  const source = (items || []).find(item => item.kind === 'source');
  if (source && source.version) return source.version;
  for (const item of items || []) {
    if (item.version) return item.version;
  }
  return '';
}

function bumpSemver(base, type) {
  const parts = base.split('.').map(x => parseInt(x, 10) || 0);
  while (parts.length < 3) parts.push(0);
  if (type === 'patch') {
    parts[2] += 1;
  } else if (type === 'minor') {
    parts[1] += 1;
    parts[2] = 0;
  }
  return parts.join('.');
}

function markHardcodedDrift(items) {
  (items || []).forEach((item) => {
    if (item.hardcoded) {
      App.log('warn', `${item.name} 仍硬编码 ${item.hardcoded}（${item.rel_path}），应改为构建期注入`);
    }
  });
}

window.VersionModule = {
  latestAndroidVersion: '',

  async refreshAndroidVersions() {
    try {
      const res = await window.pywebview.api.version_inspect(VERSION_ANDROID_GROUPS);
      if (!res.success) {
        App.log('error', `Android 版本读取失败: ${res.error || '未知错误'}`);
        return;
      }
      renderVersionRows(document.querySelector('#android-version-table tbody'), res.items);
      markHardcodedDrift(res.items);
      const latest = pickSourceVersion(res.items);
      if (latest) this.latestAndroidVersion = latest;
    } catch (e) {
      App.log('error', `Android 版本读取异常: ${e}`);
    }
  },

  bumpAndroidVersion(type) {
    if (!this.latestAndroidVersion) {
      App.toast('Android 版本状态尚未加载，请先刷新', 'warn');
      return;
    }
    const nextVer = bumpSemver(this.latestAndroidVersion, type);
    const input = document.getElementById('android-version-input');
    if (input) input.value = nextVer;
    App.toast(`已推导 Android 目标版本号: v${nextVer}`, 'ok');
  },

  async syncAndroidVersion() {
    const input = document.getElementById('android-version-input');
    const ver = input ? input.value.trim() : '';
    if (!ver) return App.toast('请输入目标新版本号 (例如 2.2.12)', 'warn');

    const dryRun = document.getElementById('android-dry-run').checked;
    const commit = document.getElementById('android-commit').checked;

    App.setBusy(true, `正在同步 Android 版本至 v${ver}...`);
    try {
      const res = await window.pywebview.api.version_sync(ver, dryRun, false, commit, VERSION_ANDROID_GROUPS);
      if (!res.started) {
        App.setBusy(false);
        App.toast(res.message || '版本同步未能启动', 'warn');
      }
    } catch (e) {
      App.setBusy(false);
      App.log('error', `Android 版本同步异常: ${e}`);
      App.toast(`Android 版本同步异常: ${e}`, 'error');
    }
  },

  onSyncDone(payload) {
    App.setBusy(false);
    if (!payload) return;

    this.refreshAndroidVersions();

    if (!payload.success) {
      App.toast(payload.message || '版本同步失败', 'error');
      return;
    }

    if (payload.target_version) this.latestAndroidVersion = payload.target_version;

    const count = payload.modified_files ? payload.modified_files.length : 0;
    const prefix = payload.dry_run ? '版本预览完成' : '版本号同步成功';
    App.toast(`${prefix}，影响文件数: ${count}`, 'ok');
  },
};
