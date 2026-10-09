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
  },

  bindTheme() {
    const toggle = document.getElementById('theme-toggle');
    toggle.addEventListener('click', () => {
      const isDark = document.body.classList.contains('theme-dark');
      document.body.classList.toggle('theme-dark', !isDark);
      document.body.classList.toggle('theme-light', isDark);
    });
  },

  bindTerminal() {
    document.getElementById('btn-log-clear').addEventListener('click', () => {
      document.getElementById('terminal-output').innerHTML = '';
    });

    document.getElementById('btn-log-copy').addEventListener('click', () => {
      const text = document.getElementById('terminal-output').innerText;
      navigator.clipboard.writeText(text).then(() => {
        alert('日志内容已成功复制到剪贴板！');
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

    if (busy) {
      dot.className = 'dot busy';
      text.textContent = label || '处理中...';
      spinner.style.display = 'inline-block';
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
  },

  handleBackendEvent(event) {
    if (!event || !event.type) return;
    const { type, data } = event;

    if (type === 'log') {
      this.log(data.level, data.message);
    } else if (type === 'dns_benchmark_done') {
      DNSModule.onBenchmarkDone(data);
    } else if (type === 'dns_verify_done') {
      DNSModule.onVerifyDone(data);
    } else if (type === 'scan_done') {
      ScannerModule.onScanDone(data);
    } else if (type === 'logo_export_done') {
      LogoModule.onExportDone(data);
    } else if (type === 'build_done') {
      BuildModule.onBuildDone(data);
    } else if (type === 'version_sync_done') {
      VersionModule.onSyncDone(data);
    } else if (type === 'capture_done') {
      CaptureModule.onCaptureDone(data);
    }
  },

  bindModuleEvents() {
    // DNS
    document.getElementById('btn-dns-query').addEventListener('click', () => DNSModule.query());
    document.getElementById('btn-dns-bench').addEventListener('click', () => DNSModule.benchmark());
    document.getElementById('btn-dns-verify').addEventListener('click', () => DNSModule.verify());

    // Scanner
    document.getElementById('btn-scan-start').addEventListener('click', () => ScannerModule.startScan());

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
      window.pywebview.api.open_explorer('Windows/frontend/src/assets/images');
    });

    // Build
    document.getElementById('btn-refresh-toolchain').addEventListener('click', () => BuildModule.refreshToolchain());
    document.getElementById('btn-build-start').addEventListener('click', () => BuildModule.startBuild());
    document.getElementById('btn-build-cancel').addEventListener('click', () => BuildModule.cancelBuild());
    document.getElementById('btn-build-open-bin').addEventListener('click', () => {
      window.pywebview.api.open_explorer('Windows/build/bin');
    });

    // Version
    document.getElementById('btn-ver-refresh').addEventListener('click', () => VersionModule.refreshVersions());
    document.getElementById('btn-ver-sync').addEventListener('click', () => VersionModule.syncVersion());

    // Capture
    document.getElementById('btn-cap-start').addEventListener('click', () => CaptureModule.startCapture());
    document.getElementById('btn-cap-open-dir').addEventListener('click', () => {
      window.pywebview.api.open_explorer('screenshots');
    });
  }
};

window.addEventListener('DOMContentLoaded', () => {
  App.init();
});
