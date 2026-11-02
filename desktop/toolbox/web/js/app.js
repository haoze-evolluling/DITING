// 谛听 (DITING) 开发者工具箱核心前端主控制器

window.App = {
  activeTab: 'dns',
  isBusy: false,

  init() {
    this.bindNavigation();
    this.bindTheme();
    this.bindTerminal();
    this.bindModuleEvents();

    // 等待 pywebview 就绪后进行初始数据拉取
    window.addEventListener('pywebviewready', () => {
      this.log('system', 'PyWebView API 桥接层已成功挂载。');
      LogoModule.refreshPreview();
      BuildModule.refreshToolchain();
      VersionModule.refreshFlutterVersions();
      VersionModule.refreshVersions();
    });

    // 监听 Python 后端推送的全局事件
    window.onBackendEvent = (payload) => {
      this.handleBackendEvent(payload);
    };
  },

  bindNavigation() {
    document.querySelectorAll('.nav-item').forEach(btn => {
      btn.addEventListener('click', () => {
        const targetTab = btn.getAttribute('data-tab');
        this.switchTab(targetTab);
      });
    });
  },

  switchTab(tabId) {
    this.activeTab = tabId;
    document.querySelectorAll('.nav-item').forEach(b => {
      b.classList.toggle('active', b.getAttribute('data-tab') === tabId);
    });
    document.querySelectorAll('.tab-pane').forEach(p => {
      p.classList.toggle('active', p.id === `pane-${tabId}`);
    });
    if (tabId === 'logo') {
      LogoModule.refreshPreview();
    } else if (tabId === 'build') {
      BuildModule.refreshToolchain();
    } else if (tabId === 'version') {
      VersionModule.refreshFlutterVersions();
      VersionModule.refreshVersions();
    }
  },

  bindTheme() {
    const toggle = document.getElementById('theme-toggle');
    toggle.addEventListener('click', () => {
      const current = document.documentElement.getAttribute('data-theme');
      const next = current === 'dark' ? 'light' : 'dark';
      window.__applyTheme(next);
      try { localStorage.setItem('diting_theme_mode', next); } catch (e) { /* 忽略 */ }
    });
  },

  toast(message, type = 'ok') {
    const host = document.getElementById('toast-host');
    if (!host) return;
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.textContent = message;
    host.appendChild(el);
    setTimeout(() => {
      el.style.transition = 'opacity 0.2s ease';
      el.style.opacity = '0';
      setTimeout(() => el.remove(), 220);
    }, 2600);
  },

  logCount: 0,

  bindTerminal() {
    document.getElementById('btn-log-clear').addEventListener('click', () => {
      document.getElementById('terminal-output').innerHTML = '';
      this.logCount = 0;
      const badge = document.getElementById('terminal-badge');
      if (badge) badge.style.display = 'none';
    });

    document.getElementById('btn-log-copy').addEventListener('click', () => {
      const text = document.getElementById('terminal-output').innerText;
      navigator.clipboard.writeText(text).then(() => {
        this.toast('日志内容已复制到剪贴板', 'ok');
      });
    });

    document.getElementById('btn-log-toggle').addEventListener('click', () => {
      const sec = document.getElementById('terminal-section');
      sec.classList.toggle('collapsed');
    });
  },

  setBusy(busy, label = '') {
    this.isBusy = busy;
    const indicator = document.getElementById('global-status');
    const dot = indicator.querySelector('.dot');
    const text = indicator.querySelector('.text');
    const spinner = document.getElementById('terminal-spinner');
    const sec = document.getElementById('terminal-section');

    if (busy) {
      dot.className = 'dot busy';
      text.textContent = label || '处理中...';
      spinner.style.display = 'inline-block';
      if (sec && sec.classList.contains('collapsed')) {
        sec.classList.remove('collapsed');
      }
    } else {
      dot.className = 'dot idle';
      text.textContent = '就绪';
      spinner.style.display = 'none';
    }
  },

  log(level, msg) {
    const output = document.getElementById('terminal-output');
    const timeStr = new Date().toTimeString().split(' ')[0];
    const div = document.createElement('div');
    div.className = `log-line log-${level}`;
    div.textContent = `[${timeStr}] [${level.toUpperCase()}] ${msg}`;
    output.appendChild(div);
    output.scrollTop = output.scrollHeight;

    this.logCount += 1;
    const badge = document.getElementById('terminal-badge');
    if (badge) {
      badge.style.display = 'inline-block';
      badge.textContent = `${this.logCount} 条`;
    }
  },

  handleBackendEvent(event) {
    if (!event || !event.type) return;
    const { type, data } = event;

    if (type === 'log') {
      this.log(data.level, data.message);
    } else if (type === 'dns_benchmark_done') {
      DNSModule.onBenchmarkDone(data);
    } else if (type === 'scan_done') {
      ScannerModule.onScanDone(data);
    } else if (type === 'logo_export_done') {
      LogoModule.onExportDone(data);
    } else if (type === 'build_done') {
      BuildModule.onBuildDone(data);
    } else if (type === 'version_sync_done') {
      VersionModule.onSyncDone(data);
    }
  },

  bindModuleEvents() {
    // DNS
    document.getElementById('btn-dns-query').addEventListener('click', () => DNSModule.query());
    document.getElementById('btn-dns-bench').addEventListener('click', () => DNSModule.benchmark());
    document.querySelectorAll('.dns-preset-row button').forEach(btn => {
      btn.addEventListener('click', () => DNSModule.setPreset(btn.getAttribute('data-dns')));
    });
    const copyAnsBtn = document.getElementById('btn-dns-copy-answers');
    if (copyAnsBtn) copyAnsBtn.addEventListener('click', () => DNSModule.copyAnswers());

    // Scanner
    document.getElementById('btn-scan-start').addEventListener('click', () => ScannerModule.startScan());
    const filterAllBtn = document.getElementById('btn-filter-all');
    if (filterAllBtn) filterAllBtn.addEventListener('click', () => ScannerModule.setFilter('all'));
    const filterExcBtn = document.getElementById('btn-filter-exceeded');
    if (filterExcBtn) filterExcBtn.addEventListener('click', () => ScannerModule.setFilter('exceeded'));

    // Logo
    const syncColor = (pickerId, textId) => {
      const p = document.getElementById(pickerId);
      const t = document.getElementById(textId);
      p.addEventListener('input', () => { t.value = p.value; LogoModule.refreshPreview(); });
      t.addEventListener('input', () => { p.value = t.value; LogoModule.refreshPreview(); });
    };
    syncColor('logo-bg-picker', 'logo-bg-text');
    syncColor('logo-totem-picker', 'logo-totem-text');
    document.getElementById('logo-gradient').addEventListener('change', () => LogoModule.refreshPreview());
    document.getElementById('btn-logo-export').addEventListener('click', () => LogoModule.exportAssets());
    document.getElementById('btn-logo-open-res').addEventListener('click', () => {
      window.pywebview.api.open_explorer('shared/assets/images');
    });

    // Build
    document.getElementById('btn-refresh-toolchain').addEventListener('click', () => BuildModule.refreshToolchain());
    document.getElementById('btn-build-start').addEventListener('click', () => BuildModule.startBuild());
    document.getElementById('btn-build-cancel').addEventListener('click', () => BuildModule.cancelBuild());
    document.getElementById('btn-build-open-bin').addEventListener('click', () => {
      window.pywebview.api.open_explorer('desktop/service/build/bin');
    });

    // Version - Flutter 客户端（常用）
    document.getElementById('btn-flutter-refresh').addEventListener('click', () => VersionModule.refreshFlutterVersions());
    document.getElementById('btn-flutter-sync').addEventListener('click', () => VersionModule.syncFlutterVersion());
    const flutterBumpPatch = document.getElementById('btn-flutter-bump-patch');
    if (flutterBumpPatch) flutterBumpPatch.addEventListener('click', () => VersionModule.bumpFlutterVersion('patch'));
    const flutterBumpMinor = document.getElementById('btn-flutter-bump-minor');
    if (flutterBumpMinor) flutterBumpMinor.addEventListener('click', () => VersionModule.bumpFlutterVersion('minor'));

    // Version - 其他模块（折叠区）
    document.getElementById('btn-ver-refresh').addEventListener('click', () => VersionModule.refreshVersions());
    document.getElementById('btn-ver-sync').addEventListener('click', () => VersionModule.syncVersion());
    const bumpPatchBtn = document.getElementById('btn-ver-bump-patch');
    if (bumpPatchBtn) bumpPatchBtn.addEventListener('click', () => VersionModule.bumpVersion('patch'));
    const bumpMinorBtn = document.getElementById('btn-ver-bump-minor');
    if (bumpMinorBtn) bumpMinorBtn.addEventListener('click', () => VersionModule.bumpVersion('minor'));
  }
};

window.addEventListener('DOMContentLoaded', () => {
  App.init();
});
