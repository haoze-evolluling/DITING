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
} from './types';

// Wails 全局对象类型声明
declare global {
  interface Window {
    go?: {
      main?: {
        App?: {
          Greet?: (name: string) => Promise<string>;
          RunEmergencyRestore?: () => Promise<string>;
          IsAutoStartEnabled?: () => Promise<boolean>;
          SetAutoStart?: (enable: boolean) => Promise<boolean>;
        };
      };
    };
  }
}

class IPCService {
  private baseURL: string = 'http://127.0.0.1:15353';
  private token: string = '';
  private ws: WebSocket | null = null;
  private wsReconnectTimer: any = null;
  private isConnectingWS: boolean = false;
  private eventListeners: Set<(event: WebSocketEvent) => void> = new Set();
  private connectionStatusListeners: Set<(connected: boolean) => void> = new Set();
  public isConnected: boolean = false;

  constructor() {
    this.loadConfig();
  }

  public loadConfig() {
    const savedHost = localStorage.getItem('diting_ipc_host') || '127.0.0.1';
    const savedPort = localStorage.getItem('diting_ipc_port') || '15353';
    this.token = localStorage.getItem('diting_ipc_token') || '';
    this.baseURL = `http://${savedHost}:${savedPort}`;
  }

  public saveConfig(host: string, port: string, token: string) {
    localStorage.setItem('diting_ipc_host', host);
    localStorage.setItem('diting_ipc_port', port);
    localStorage.setItem('diting_ipc_token', token);
    this.baseURL = `http://${host}:${port}`;
    this.token = token;
    this.reconnectWS();
  }

  public getConfig() {
    const savedHost = localStorage.getItem('diting_ipc_host') || '127.0.0.1';
    const savedPort = localStorage.getItem('diting_ipc_port') || '15353';
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
        throw new Error('鉴权失败: Token 无效或未提供');
      }
      const json: ApiResponse<T> = await resp.json();
      if (!json.success) {
        throw new Error(json.error || json.message || '请求失败');
      }
      this.setConnected(true);
      return json.data as T;
    } catch (err: any) {
      if (err instanceof TypeError || (err.message && (err.message.includes('fetch') || err.message.includes('Network') || err.message.includes('failed')))) {
        this.setConnected(false);
      }
      throw err;
    }
  }

  private setConnected(connected: boolean) {
    if (this.isConnected !== connected) {
      this.isConnected = connected;
      this.connectionStatusListeners.forEach((fn) => fn(connected));
    }
  }

  public onConnectionChange(fn: (connected: boolean) => void) {
    this.connectionStatusListeners.add(fn);
    fn(this.isConnected);
    return () => this.connectionStatusListeners.delete(fn);
  }

  // --- RESTful 控制接口 ---

  public async getStatus(): Promise<StatusResponse> {
    return this.request<StatusResponse>('/api/v1/status');
  }

  public async checkHealth(): Promise<boolean> {
    try {
      await this.request<string>('/api/v1/health');
      this.setConnected(true);
      return true;
    } catch {
      this.setConnected(false);
      return false;
    }
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

  public async checkPortConflicts(): Promise<PortCheckResult> {
    return this.request<PortCheckResult>('/api/v1/portcheck');
  }

  // --- WebSocket 实时事件订阅 ---

  public connectWS() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    if (this.isConnectingWS) return;
    this.isConnectingWS = true;

    const host = this.baseURL.replace(/^http:\/\//, '').replace(/^https:\/\//, '');
    let wsUrl = `ws://${host}/api/v1/events`;
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

      this.ws.onmessage = (evt) => {
        try {
          const parsed: WebSocketEvent = JSON.parse(evt.data);
          this.eventListeners.forEach((listener) => listener(parsed));
        } catch (e) {
          console.error('[WS Parse Error]', e);
        }
      };

      this.ws.onerror = () => {
        this.isConnectingWS = false;
        this.setConnected(false);
      };

      this.ws.onclose = () => {
        this.isConnectingWS = false;
        this.ws = null;
        this.scheduleReconnectWS();
      };
    } catch {
      this.isConnectingWS = false;
      this.scheduleReconnectWS();
    }
  }

  public reconnectWS() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.connectWS();
  }

  private scheduleReconnectWS() {
    if (this.wsReconnectTimer) return;
    this.wsReconnectTimer = setTimeout(() => {
      this.wsReconnectTimer = null;
      this.connectWS();
    }, 3000);
  }

  public onEvent(listener: (event: WebSocketEvent) => void) {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  // --- 智能缓存 (Phase 5) API ---

  public async getCacheStats(): Promise<CacheStats> {
    return this.request<CacheStats>('/api/v1/cache/stats');
  }

  public async getCacheEntries(query: string = '', limit: number = 100): Promise<CacheEntriesResponse> {
    const params = new URLSearchParams();
    if (query) params.set('query', query);
    if (limit > 0) params.set('limit', String(limit));
    const path = `/api/v1/cache/entries${params.toString() ? '?' + params.toString() : ''}`;
    return this.request<CacheEntriesResponse>(path);
  }

  public async getCacheTopDomains(limit: number = 10): Promise<CacheDomainStat[]> {
    return this.request<CacheDomainStat[]>(`/api/v1/cache/top?limit=${limit}`);
  }

  public async clearCache(): Promise<void> {
    await this.request('/api/v1/cache/clear', { method: 'POST' });
  }

  public async getCacheConfig(): Promise<CacheConfig> {
    return this.request<CacheConfig>('/api/v1/cache/config');
  }

  public async updateCacheConfig(config: Partial<CacheConfig>): Promise<void> {
    await this.request('/api/v1/cache/config', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }

  // --- 规则过滤相关接口 ---

  public async getFilterStats(): Promise<FilterStats> {
    return this.request<FilterStats>('/api/v1/filter/stats');
  }

  public async getFilterConfig(): Promise<FilterConfig> {
    return this.request<FilterConfig>('/api/v1/filter/config');
  }

  public async updateFilterConfig(config: Partial<FilterConfig>): Promise<void> {
    await this.request('/api/v1/filter/config', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }

  public async getFilterLists(): Promise<FilterList[]> {
    const res = await this.request<{ total: number; lists: FilterList[] }>('/api/v1/filter/lists');
    return res?.lists || [];
  }

  public async addFilterList(list: Partial<FilterList>): Promise<void> {
    await this.request('/api/v1/filter/lists/add', {
      method: 'POST',
      body: JSON.stringify(list),
    });
  }

  public async updateFilterList(list: FilterList): Promise<void> {
    await this.request('/api/v1/filter/lists/update', {
      method: 'POST',
      body: JSON.stringify(list),
    });
  }

  public async deleteFilterList(id: string): Promise<void> {
    await this.request('/api/v1/filter/lists/delete', {
      method: 'POST',
      body: JSON.stringify({ id }),
    });
  }

  public async refreshFilterLists(id?: string): Promise<void> {
    await this.request('/api/v1/filter/lists/refresh', {
      method: 'POST',
      body: JSON.stringify({ id: id || '' }),
    });
  }

  public async getCustomRules(): Promise<string[]> {
    const res = await this.request<{ rules: string[] }>('/api/v1/filter/rules');
    return res?.rules || [];
  }

  public async setCustomRules(rules: string[]): Promise<void> {
    await this.request('/api/v1/filter/rules', {
      method: 'POST',
      body: JSON.stringify({ rules }),
    });
  }

  public async checkHost(domain: string, qtype?: string): Promise<CheckHostResult> {
    return this.request<CheckHostResult>('/api/v1/filter/check', {
      method: 'POST',
      body: JSON.stringify({ domain, qtype }),
    });
  }

  // --- Wails 原生能力桥接 ---

  public async runNativeEmergencyRestore(): Promise<string> {
    if (window.go?.main?.App?.RunEmergencyRestore) {
      return await window.go.main.App.RunEmergencyRestore();
    }
    // 回退到 IPC 接口
    await this.disableTakeover();
    return '已通过 IPC 还原网卡 DNS 接管';
  }

  public async isAutoStartEnabled(): Promise<boolean> {
    if (window.go?.main?.App?.IsAutoStartEnabled) {
      try {
        return await window.go.main.App.IsAutoStartEnabled();
      } catch (e) {
        console.warn('获取开机自启状态失败:', e);
      }
    }
    return false;
  }

  public async setAutoStart(enable: boolean): Promise<boolean> {
    if (window.go?.main?.App?.SetAutoStart) {
      return await window.go.main.App.SetAutoStart(enable);
    }
    return enable;
  }
}

export const ipc = new IPCService();
