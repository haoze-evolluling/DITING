// 谛听 (DITING) 开发者工具箱各模块业务逻辑控制器

window.DNSModule = {
  async query() {
    const domain = document.getElementById('dns-domain').value.trim();
    const server = document.getElementById('dns-server').value.trim();
    const port = parseInt(document.getElementById('dns-port').value) || 53;
    const qtype = document.getElementById('dns-qtype').value;
    const tcp = document.getElementById('dns-tcp').checked;

    if (!domain) return alert('请输入目标域名');

    App.setBusy(true, '正在发送 DNS 查询...');
    try {
      const res = await window.pywebview.api.dns_query(domain, server, port, qtype, tcp);
      this.renderQueryResult(res);
    } catch (e) {
      App.log('error', `DNS 查询异常: ${e}`);
    } finally {
      App.setBusy(false);
    }
  },

  async benchmark() {
    const domain = document.getElementById('dns-domain').value.trim();
    const server = document.getElementById('dns-server').value.trim();
    const port = parseInt(document.getElementById('dns-port').value) || 53;
    const qtype = document.getElementById('dns-qtype').value;
    const tcp = document.getElementById('dns-tcp').checked;

    if (!domain) return alert('请输入目标域名');

    App.setBusy(true, '正在进行批量 DNS 压测...');
    document.getElementById('dns-result-container').style.display = 'block';
    document.getElementById('dns-answers-card').style.display = 'none';
    await window.pywebview.api.dns_benchmark(domain, server, port, qtype, 5, tcp);
  },

  renderQueryResult(res) {
    const container = document.getElementById('dns-result-container');
    container.style.display = 'block';

    const grid = document.getElementById('dns-stats-grid');
    const isOk = res.success && res.rcode === 'NOERROR';
    grid.innerHTML = `
      <div class="stat-box">
        <span class="stat-label">响应状态</span>
        <span class="stat-value" style="color: ${isOk ? '#10b981' : '#ef4444'}">${res.rcode || 'FAIL'}</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">查询耗时</span>
        <span class="stat-value">${res.elapsed_ms || 0} ms</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">传输协议</span>
        <span class="stat-value">${res.proto || 'UDP'}</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">记录数量</span>
        <span class="stat-value">${res.answers ? res.answers.length : 0} 条</span>
      </div>
    `;

    const answersCard = document.getElementById('dns-answers-card');
    const tbody = document.querySelector('#dns-table tbody');
    tbody.innerHTML = '';
    if (res.answers && res.answers.length > 0) {
      answersCard.style.display = 'block';
      res.answers.forEach(a => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${a.name}</td>
          <td><span class="badge badge-pass">${a.type}</span></td>
          <td>${a.ttl}s</td>
          <td style="font-family: var(--font-mono)">${a.value}</td>
        `;
        tbody.appendChild(tr);
      });
    } else {
      answersCard.style.display = 'none';
    }
  },

  onBenchmarkDone(payload) {
    App.setBusy(false);
    if (!payload.success || !payload.data) return;
    const d = payload.data;
    const grid = document.getElementById('dns-stats-grid');
    grid.innerHTML = `
      <div class="stat-box">
        <span class="stat-label">测试轮次</span>
        <span class="stat-value">${d.success_count}/${d.count}</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">丢包率</span>
        <span class="stat-value">${d.loss_rate}%</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">平均延迟</span>
        <span class="stat-value">${d.avg_ms} ms</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">极值 (Min/Max)</span>
        <span class="stat-value" style="font-size: 16px;">${d.min_ms} / ${d.max_ms} ms</span>
      </div>
    `;
  }
};

window.ScannerModule = {
  async startScan() {
    const dir = document.getElementById('scan-dir').value.trim();
    const exts = document.getElementById('scan-exts').value.trim() || '.kt,.go,.ts,.vue,.py';
    const threshold = parseInt(document.getElementById('scan-threshold').value) || 600;
    const showAll = document.getElementById('scan-all').checked;

    App.setBusy(true, '正在扫描项目源文件规模...');
    await window.pywebview.api.scan_files(dir, exts, threshold, showAll);
  },

  onScanDone(payload) {
    App.setBusy(false);
    if (!payload.success || !payload.data) return;
    const d = payload.data;
    document.getElementById('scan-result-container').style.display = 'block';

    const grid = document.getElementById('scan-stats-grid');
    grid.innerHTML = `
      <div class="stat-box">
        <span class="stat-label">扫描文件总数</span>
        <span class="stat-value">${d.stats.total_scanned}</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">代码总行数</span>
        <span class="stat-value">${d.stats.total_lines.toLocaleString()}</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">超标文件 (&gt;${d.threshold}行)</span>
        <span class="stat-value" style="color: ${d.exceeded_count > 0 ? '#ef4444' : '#10b981'}">${d.exceeded_count}</span>
      </div>
      <div class="stat-box">
        <span class="stat-label">最大单个文件行数</span>
        <span class="stat-value">${d.max_file ? d.max_file.line_count : 0}</span>
      </div>
    `;

    document.getElementById('scan-matched-count').textContent = d.matched_files.length;
    const tbody = document.querySelector('#scan-table tbody');
    tbody.innerHTML = '';
    d.matched_files.forEach((item, idx) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${idx + 1}</td>
        <td style="font-weight: 600; color: ${item.exceeded ? '#ef4444' : 'inherit'}">${item.line_count} 行</td>
        <td><span class="badge ${item.ext === '.kt' ? 'badge-pass' : 'badge-warn'}">${item.ext.toUpperCase()}</span></td>
        <td style="font-family: var(--font-mono); font-size: 12px;">${item.rel_path}</td>
        <td><button class="btn btn-sm btn-ghost" onclick="window.pywebview.api.open_explorer('${item.full_path.replace(/\\/g, '\\\\')}')">打开</button></td>
      `;
      tbody.appendChild(tr);
    });
  }
};

window.LogoModule = {
  async refreshPreview() {
    const bg = document.getElementById('logo-bg-text').value.trim();
    const totem = document.getElementById('logo-totem-text').value.trim();
    const gradient = document.getElementById('logo-gradient').checked;

    try {
      const res = await window.pywebview.api.logo_preview(bg, totem, gradient);
      if (res.success) {
        document.getElementById('logo-preview-box').innerHTML = res.svg;
      }
    } catch (e) {
      console.error(e);
    }
  },

  async exportAssets() {
    const bg = document.getElementById('logo-bg-text').value.trim();
    const totem = document.getElementById('logo-totem-text').value.trim();
    const gradient = document.getElementById('logo-gradient').checked;

    App.setBusy(true, '正在生成各尺寸 PNG 与 ICO 图标...');
    await window.pywebview.api.logo_export(bg, totem, gradient, null);
  },

  onExportDone(payload) {
    App.setBusy(false);
    if (payload.success) {
      alert('Logo 资源导出成功！SVG、1024/512 图标及 Windows ICO 已就绪。');
    }
  }
};

window.BuildModule = {
  async refreshToolchain() {
    try {
      const tools = await window.pywebview.api.build_get_toolchain();
      const grid = document.getElementById('toolchain-grid');
      grid.innerHTML = '';
      Object.entries(tools).forEach(([k, info]) => {
        const chip = document.createElement('div');
        chip.className = `tool-chip ${info.found ? '' : 'missing'}`;
        chip.innerHTML = `
          <span class="chip-dot"></span>
          <span><strong>${k.toUpperCase()}</strong>: ${info.version || (info.found ? '已就绪' : '未安装')}</span>
        `;
        grid.appendChild(chip);
      });
    } catch (e) {
      console.error(e);
    }
  },

  async startBuild() {
    const target = document.getElementById('build-target').value;
    const version = document.getElementById('build-version').value.trim() || '1.3.1';
    const buildType = document.getElementById('build-type').value;
    const clean = document.getElementById('build-clean').checked;

    App.setBusy(true, `正在执行 ${target} 构建流水线...`);
    document.getElementById('btn-build-cancel').disabled = false;
    await window.pywebview.api.build_start(target, version, buildType, clean, false);
  },

  async cancelBuild() {
    await window.pywebview.api.cancel_current_task();
  },

  onBuildDone(payload) {
    App.setBusy(false);
    document.getElementById('btn-build-cancel').disabled = true;
    if (payload.success) {
      alert(`构建流水线完成！产物已输出至 build/bin 目录。`);
    } else {
      alert(`构建未成功: ${payload.message || '未知错误'}`);
    }
  }
};

window.VersionModule = {
  async refreshVersions() {
    try {
      const res = await window.pywebview.api.version_inspect();
      if (!res.success) return;
      const tbody = document.querySelector('#version-table tbody');
      tbody.innerHTML = '';
      res.items.forEach(item => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td><strong>${item.name}</strong></td>
          <td><span class="badge badge-pass">${item.version}</span></td>
          <td style="font-family: var(--font-mono); font-size: 12px;">${item.rel_path}</td>
        `;
        tbody.appendChild(tr);
      });
    } catch (e) {
      console.error(e);
    }
  },

  async syncVersion() {
    const ver = document.getElementById('target-version-input').value.trim();
    if (!ver) return alert('请输入目标新版本号 (例如 1.4.0)');

    const dryRun = document.getElementById('ver-dry-run').checked;
    const verify = document.getElementById('ver-verify').checked;
    const commit = document.getElementById('ver-commit').checked;

    App.setBusy(true, `正在同步各模块版本至 v${ver}...`);
    await window.pywebview.api.version_sync(ver, dryRun, verify, commit);
  },

  onSyncDone(payload) {
    App.setBusy(false);
    this.refreshVersions();
    if (payload.success) {
      alert(`版本号同步成功！影响文件数: ${payload.modified_files ? payload.modified_files.length : 0}`);
    }
  }
};

window.CaptureModule = {
  async startCapture() {
    const tab = document.getElementById('cap-tab').value;
    const theme = document.getElementById('cap-theme').value;
    const width = parseInt(document.getElementById('cap-width').value) || 1280;
    const height = parseInt(document.getElementById('cap-height').value) || 720;

    App.setBusy(true, '正在启动无头浏览器并截取界面...');
    await window.pywebview.api.capture_start(tab, theme, width, height, null);
  },

  onCaptureDone(payload) {
    App.setBusy(false);
    if (!payload.success || !payload.files) return;
    const card = document.getElementById('cap-gallery-card');
    card.style.display = 'block';
    document.getElementById('cap-count').textContent = payload.files.length;

    const grid = document.getElementById('cap-gallery-grid');
    grid.innerHTML = '';
    payload.files.forEach(f => {
      const div = document.createElement('div');
      div.className = 'gallery-item';
      div.onclick = () => window.pywebview.api.open_explorer(f.path);
      div.innerHTML = `
        <div style="font-size: 24px; text-align: center; padding: 12px 0;">🖼️</div>
        <div class="item-title" title="${f.name}">${f.name}</div>
        <div style="font-size: 11px; color: var(--text-dim); margin-top: 2px;">${f.size_kb} KB</div>
      `;
      grid.appendChild(div);
    });
  }
};
