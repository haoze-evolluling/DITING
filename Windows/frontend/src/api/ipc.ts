import type {
  ApiResponse,
  StatusResponse,
  AdapterInfo,
  PortCheckResult,
  WebSocketEvent,
  UpstreamConfigureRequest,
  TestUpstreamRequest,
  TestUpstreamResponse,
  CacheStats,
  CacheConfig,
  CacheEntriesResponse,
  CacheDomainStat,
  FilterStats,
  FilterConfig,
  FilterList,
  CheckHostResult,
  CoreServiceStatus,
  BootstrapConfig,
  LANStatusResponse,
  ConfigureLANRequest,
  AuthStatusResponse,
  LoginRequest,
  LoginResponse,
  SetupAuthRequest,
  ChangePasswordRequest,
  WebStatusResponse,
  ConfigureWebRequest,
} from './types';
import { nativeBridge } from './native';

class IPCService {
  private baseURL: string = 'http://127.0.0.1:15353';
  private token: string = '';
  private ws: WebSocket | null = null;
  private wsReconnectTimer: any = null;
  private isConnectingWS: boolean = false;
  private eventListeners: Set<(event: WebSocketEvent) => void> = new Set();
  private connectionStatusListeners: Set<(connected: boolean) => void> = new Set();
  private authStatusListeners: Set<(authRequired: boolean) => void> = new Set();
  public isConnected: boolean = false;

  constructor() {
    this.loadConfig();
  }

  public isWebMode(): boolean {
    return !nativeBridge.isDesktopApp();
  }

  public loadConfig() {
    const isBrowser = typeof window !== 'undefined' && !window.go?.main?.App;
    this.token = localStorage.getItem('diting_session_token') || localStorage.getItem('diting_ipc_token') || '';

    if (isBrowser && window.location.hostname) {
      const customHost = localStorage.getItem('diting_ipc_custom_host');
      const customPort = localStorage.getItem('diting_ipc_custom_port');
      if (customHost && customPort) {
        const protocol = window.location.protocol === 'https:' ? 'https:' : 'http:';
        this.baseURL = `${protocol}//${customHost}:${customPort}`;
      } else {
        this.baseURL = window.location.origin;
      }
    } else {
      const savedHost = localStorage.getItem('diting_ipc_host') || '127.0.0.1';
      const savedPort = localStorage.getItem('diting_ipc_port') || '15353';
      this.baseURL = `http://${savedHost}:${savedPort}`;
    }
  }

  public saveConfig(host: string, port: string, token: string) {
    const isBrowser = typeof window !== 'undefined' && !window.go?.main?.App;
    if (isBrowser) {
      localStorage.setItem('diting_ipc_custom_host', host);
      localStorage.setItem('diting_ipc_custom_port', port);
    }
    localStorage.setItem('diting_ipc_host', host);
    localStorage.setItem('diting_ipc_port', port);
    localStorage.setItem('diting_ipc_token', token);
    this.baseURL = `http://${host}:${port}`;
    this.token = token;
    this.reconnectWS();
  }

  public getConfig() {
    const isBrowser = typeof window !== 'undefined' && !window.go?.main?.App;
    let defHost = '127.0.0.1';
    let defPort = '15353';
    if (isBrowser && window.location.hostname) {
      defHost = window.location.hostname;
      defPort = window.location.port || (window.location.protocol === 'https:' ? '443' : '80');
    }
    const savedHost = localStorage.getItem('diting_ipc_custom_host') || localStorage.getItem('diting_ipc_host') || defHost;
    const savedPort = localStorage.getItem('diting_ipc_custom_port') || localStorage.getItem('diting_ipc_port') || defPort;
    return {
      host: savedHost,
      port: savedPort,
      token: this.token,
    };
  }

  private async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const url = `${this.baseURL}${path}`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>),
    };
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
      headers['X-API-Token'] = this.token;
    }

    try {
      const resp = await fetch(url, { ...options, headers });
      if (resp.status === 401) {
        this.notifyAuthRequired(true);
        throw new Error('未授权或登录已过期，请重新登录');
      }
      const json: ApiResponse<T> = await resp.json();
      if (!json.success) {
        const err: any = new Error(json.error || json.message || '请求失败');
        if (json.conflict) {
          err.conflict = json.conflict;
        }
        throw err;
      }
      this.setConnected(true);
      return json.data as T;
    } catch (err: any) {
      if (err.message && err.message.includes('未授权')) {
        throw err;
      }
      if (err.message && (err.message.includes('Failed to fetch') || err.message.includes('NetworkError'))) {
        this.setConnected(false);
      }
      throw err;
    }
  }

  public setConnected(connected: boolean) {
    if (this.isConnected !== connected) {
      this.isConnected = connected;
      this.connectionStatusListeners.forEach(listener => listener(connected));
    }
  }

  public onConnectionChange(listener: (connected: boolean) => void): () => void {
    this.connectionStatusListeners.add(listener);
    listener(this.isConnected);
    return () => {
      this.connectionStatusListeners.delete(listener);
    };
  }

  public onAuthRequired(listener: (required: boolean) => void): () => void {
    this.authStatusListeners.add(listener);
    return () => {
      this.authStatusListeners.delete(listener);
    };
  }

  private notifyAuthRequired(required: boolean) {
    this.authStatusListeners.forEach(listener => listener(required));
  }

  public connectWS() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    if (this.isConnectingWS) return;
    this.isConnectingWS = true;

    const isBrowser = typeof window !== 'undefined' && !window.go?.main?.App;
    const wsProtocol = this.baseURL.startsWith('https') ? 'wss' : 'ws';
    let hostPort = this.baseURL.replace(/^https?:\/\//, '');
    if (isBrowser && !localStorage.getItem('diting_ipc_custom_host') && window.location.host) {
      hostPort = window.location.host;
    }
    let wsUrl = `${wsProtocol}://${hostPort}/api/v1/events`;
    if (this.token) {
      wsUrl += `?token=${encodeURIComponent(this.token)}`;
    }

    try {
      this.ws = new WebSocket(wsUrl);
      this.ws.onopen = () => {
        this.isConnectingWS = false;
        this.setConnected(true);
        if (this.wsReconnectTimer) {
          clearTimeout(this.wsReconnectTimer);
          this.wsReconnectTimer = null;
        }
      };

      this.ws.onmessage = (event) => {
        try {
          const parsed: WebSocketEvent = JSON.parse(event.data);
          this.eventListeners.forEach(listener => listener(parsed));
        } catch (e) {
          console.error('Failed to parse WebSocket event:', e);
        }
      };

      this.ws.onclose = () => {
        this.isConnectingWS = false;
        this.scheduleWSRetry();
      };

      this.ws.onerror = () => {
        this.isConnectingWS = false;
        this.setConnected(false);
      };
    } catch {
      this.isConnectingWS = false;
      this.scheduleWSRetry();
    }
  }

  private scheduleWSRetry() {
    if (!this.wsReconnectTimer) {
      this.wsReconnectTimer = setTimeout(() => {
        this.wsReconnectTimer = null;
        this.connectWS();
      }, 3000);
    }
  }

  public reconnectWS() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.connectWS();
  }

  public onEvent(listener: (event: WebSocketEvent) => void): () => void {
    this.eventListeners.add(listener);
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      this.connectWS();
    }
    return () => {
      this.eventListeners.delete(listener);
    };
  }

  // --- 核心网络与 DNS 状态操作 ---
  public async getStatus(): Promise<StatusResponse> {
    return this.request<StatusResponse>('/api/v1/status');
  }

  public async startDNS(): Promise<void> {
    await this.request<void>('/api/v1/dns/start', { method: 'POST' });
  }

  public async stopDNS(): Promise<void> {
    await this.request<void>('/api/v1/dns/stop', { method: 'POST' });
  }

  public async enableTakeover(): Promise<void> {
    await this.request<void>('/api/v1/takeover/enable', { method: 'POST' });
  }

  public async disableTakeover(): Promise<void> {
    await this.request<void>('/api/v1/takeover/disable', { method: 'POST' });
  }

  public async getAdapters(): Promise<AdapterInfo[]> {
    return this.request<AdapterInfo[]>('/api/v1/adapters');
  }

  public async setAdapterTakeover(adapterId: string, enable: boolean): Promise<void> {
    await this.request<void>('/api/v1/takeover/adapter', {
      method: 'POST',
      body: JSON.stringify({ adapterId, enable }),
    });
  }

  public async checkPortConflicts(): Promise<PortCheckResult> {
    return this.request<PortCheckResult>('/api/v1/portcheck');
  }

  public async autofixPortConflicts(startDNS: boolean = false): Promise<PortCheckResult> {
    return this.request<PortCheckResult>('/api/v1/portcheck/autofix', {
      method: 'POST',
      body: JSON.stringify({ startDNS }),
    });
  }

  public async checkHealth(): Promise<boolean> {
    try {
      const res = await this.request<string>('/api/v1/health');
      return res === 'ok';
    } catch {
      return false;
    }
  }

  // --- 上游与 Bootstrap 引导 ---
  public async configureUpstream(req: UpstreamConfigureRequest): Promise<void> {
    await this.request<void>('/api/v1/upstream/configure', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public async testUpstream(req: TestUpstreamRequest): Promise<TestUpstreamResponse> {
    return this.request<TestUpstreamResponse>('/api/v1/upstream/test', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public async configureBootstrap(config: BootstrapConfig): Promise<void> {
    await this.request<void>('/api/v1/bootstrap/configure', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }

  // --- 智能缓存系统 ---
  public async getCacheStats(): Promise<CacheStats> {
    return this.request<CacheStats>('/api/v1/cache/stats');
  }

  public async getCacheEntries(query: string = '', limit: number = 50): Promise<CacheEntriesResponse> {
    const params = new URLSearchParams();
    if (query) params.set('q', query);
    if (limit) params.set('limit', limit.toString());
    return this.request<CacheEntriesResponse>(`/api/v1/cache/entries?${params.toString()}`);
  }

  public async getCacheTopDomains(limit: number = 10): Promise<CacheDomainStat[]> {
    return this.request<CacheDomainStat[]>(`/api/v1/cache/top?limit=${limit}`);
  }

  public async clearCache(): Promise<void> {
    await this.request<void>('/api/v1/cache/clear', { method: 'POST' });
  }

  public async getCacheConfig(): Promise<CacheConfig> {
    return this.request<CacheConfig>('/api/v1/cache/config');
  }

  public async updateCacheConfig(config: CacheConfig): Promise<void> {
    await this.request<void>('/api/v1/cache/config', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }

  // --- 规则拦截模块 ---
  public async getFilterStats(): Promise<FilterStats> {
    return this.request<FilterStats>('/api/v1/filter/stats');
  }

  public async getFilterConfig(): Promise<FilterConfig> {
    return this.request<FilterConfig>('/api/v1/filter/config');
  }

  public async updateFilterConfig(config: Partial<FilterConfig>): Promise<void> {
    await this.request<void>('/api/v1/filter/config', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }

  public async getFilterLists(): Promise<FilterList[]> {
    const res = await this.request<{ total: number; lists: FilterList[] }>('/api/v1/filter/lists');
    return res.lists || [];
  }

  public async addFilterList(list: Partial<FilterList>): Promise<void> {
    await this.request<void>('/api/v1/filter/lists/add', {
      method: 'POST',
      body: JSON.stringify(list),
    });
  }

  public async updateFilterList(list: FilterList): Promise<void> {
    await this.request<void>('/api/v1/filter/lists/update', {
      method: 'POST',
      body: JSON.stringify(list),
    });
  }

  public async deleteFilterList(id: string): Promise<void> {
    await this.request<void>('/api/v1/filter/lists/delete', {
      method: 'POST',
      body: JSON.stringify({ id }),
    });
  }

  public async refreshFilterLists(id: string = ''): Promise<void> {
    await this.request<void>('/api/v1/filter/lists/refresh', {
      method: 'POST',
      body: JSON.stringify({ id }),
    });
  }

  public async getCustomRules(): Promise<string[]> {
    const res = await this.request<{ rules: string[] }>('/api/v1/filter/rules');
    return res.rules || [];
  }

  public async setCustomRules(rules: string[]): Promise<void> {
    await this.request<void>('/api/v1/filter/rules', {
      method: 'POST',
      body: JSON.stringify({ rules }),
    });
  }

  public async checkHost(domain: string, qtype: string | number = 'A'): Promise<CheckHostResult> {
    return this.request<CheckHostResult>('/api/v1/filter/check', {
      method: 'POST',
      body: JSON.stringify({ domain, qtype: String(qtype) }),
    });
  }

  // --- 局域网 DNS 服务 ---
  public async getLANStatus(): Promise<LANStatusResponse> {
    return this.request<LANStatusResponse>('/api/v1/dns/lan');
  }

  public async configureLAN(req: ConfigureLANRequest): Promise<void> {
    await this.request<void>('/api/v1/dns/lan/configure', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public async configureFirewall(enable: boolean): Promise<string> {
    if (window.go?.main?.App?.ConfigureFirewallForLAN) {
      try {
        return await window.go.main.App.ConfigureFirewallForLAN(enable);
      } catch {}
    }
    const res = await this.request<string>('/api/v1/dns/lan/firewall', {
      method: 'POST',
      body: JSON.stringify({ enable }),
    });
    return res || (enable ? '已成功放行 53 端口防火墙规则' : '已成功移除 53 端口防火墙规则');
  }

  // --- Web 远程管理与认证 ---
  public async getAuthStatus(): Promise<AuthStatusResponse> {
    return this.request<AuthStatusResponse>('/api/v1/auth/status');
  }

  public async login(req: LoginRequest): Promise<LoginResponse> {
    const res = await this.request<LoginResponse>('/api/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify(req),
    });
    if (res?.token) {
      this.token = res.token;
      localStorage.setItem('diting_session_token', res.token);
      localStorage.setItem('diting_session_user', res.username);
      this.reconnectWS();
      this.notifyAuthRequired(false);
    }
    return res;
  }

  public async logout(): Promise<void> {
    try {
      await this.request<void>('/api/v1/auth/logout', { method: 'POST' });
    } catch {}
    this.token = '';
    localStorage.removeItem('diting_session_token');
    localStorage.removeItem('diting_session_user');
    this.notifyAuthRequired(true);
  }

  public async setupAuth(req: SetupAuthRequest): Promise<void> {
    await this.request<void>('/api/v1/auth/setup', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public async changePassword(req: ChangePasswordRequest): Promise<void> {
    await this.request<void>('/api/v1/auth/password', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public async getWebStatus(): Promise<WebStatusResponse> {
    return this.request<WebStatusResponse>('/api/v1/web/status');
  }

  public async configureWeb(req: ConfigureWebRequest): Promise<void> {
    await this.request<void>('/api/v1/web/configure', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public async configureWebFirewall(enable: boolean): Promise<string> {
    const res = await this.request<string>('/api/v1/web/firewall', {
      method: 'POST',
      body: JSON.stringify({ enable }),
    });
    return res || (enable ? '已成功放行 Web 端口防火墙规则' : '已成功移除 Web 端口防火墙规则');
  }

  // --- Wails 原生平台委托 ---
  public runNativeEmergencyRestore() { return nativeBridge.runNativeEmergencyRestore(); }
  public isAutoStartEnabled() { return nativeBridge.isAutoStartEnabled(); }
  public setAutoStart(enable: boolean) { return nativeBridge.setAutoStart(enable); }
  public getCoreServiceStatus() { return nativeBridge.getCoreServiceStatus(); }
  public startCoreService() { return nativeBridge.startCoreService(); }
  public stopCoreService() { return nativeBridge.stopCoreService(); }
  public restartCoreService() { return nativeBridge.restartCoreService(); }
  public installCoreService() { return nativeBridge.installCoreService(); }
  public installAndStartCoreService() { return nativeBridge.installAndStartCoreService(); }
  public uninstallCoreService() { return nativeBridge.uninstallCoreService(); }
}

export const ipc = new IPCService();
