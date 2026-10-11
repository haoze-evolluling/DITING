import type { ApiResponse } from './types';
import { isDesktopApp } from '../utils/env';

/**
 * HTTP 传输层：负责基址 / Token 管理、请求封装、连接状态与鉴权失效广播。
 */
export class HttpTransport {
  public baseURL = 'http://127.0.0.1:15353';
  public token = '';
  public isConnected = false;

  private connectionListeners: Set<(connected: boolean) => void> = new Set();
  private authListeners: Set<(required: boolean) => void> = new Set();

  constructor() {
    this.loadConfig();
  }

  public loadConfig() {
    const isBrowser = !isDesktopApp();
    try {
      this.token = localStorage.getItem('diting_session_token') || localStorage.getItem('diting_ipc_token') || '';

      if (isBrowser && typeof window !== 'undefined' && window.location.hostname) {
        const customHost = localStorage.getItem('diting_ipc_custom_host');
        const customPort = localStorage.getItem('diting_ipc_custom_port');
        if (customHost && customPort) {
          const protocol = window.location.protocol === 'https:' ? 'https:' : 'http:';
          this.baseURL = `${protocol}//${customHost}:${customPort}`;
        } else {
          this.baseURL = window.location.origin;
        }
      } else if (typeof localStorage !== 'undefined') {
        const savedHost = localStorage.getItem('diting_ipc_host') || '127.0.0.1';
        const savedPort = localStorage.getItem('diting_ipc_port') || '15353';
        this.baseURL = `http://${savedHost}:${savedPort}`;
      }
    } catch {}
  }

  public saveConfig(host: string, port: string, token: string) {
    try {
      if (!isDesktopApp()) {
        localStorage.setItem('diting_ipc_custom_host', host);
        localStorage.setItem('diting_ipc_custom_port', port);
      }
      localStorage.setItem('diting_ipc_host', host);
      localStorage.setItem('diting_ipc_port', port);
      localStorage.setItem('diting_ipc_token', token);
    } catch {}

    this.baseURL = `http://${host}:${port}`;
    this.token = token;
  }

  public getConfig() {
    let defHost = '127.0.0.1';
    let defPort = '15353';
    if (!isDesktopApp() && typeof window !== 'undefined' && window.location.hostname) {
      defHost = window.location.hostname;
      defPort = window.location.port || (window.location.protocol === 'https:' ? '443' : '80');
    }
    try {
      return {
        host: localStorage.getItem('diting_ipc_custom_host') || localStorage.getItem('diting_ipc_host') || defHost,
        port: localStorage.getItem('diting_ipc_custom_port') || localStorage.getItem('diting_ipc_port') || defPort,
        token: this.token,
      };
    } catch {
      return { host: defHost, port: defPort, token: this.token };
    }
  }

  public setSession(token: string) {
    this.token = token;
    try {
      localStorage.setItem('diting_session_token', token);
    } catch {}
  }

  public clearSession() {
    this.token = '';
    try {
      localStorage.removeItem('diting_session_token');
      localStorage.removeItem('diting_session_user');
    } catch {}
  }

  public async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>),
    };
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
      headers['X-API-Token'] = this.token;
    }

    try {
      const resp = await fetch(`${this.baseURL}${path}`, { ...options, headers });
      if (resp.status === 401) {
        this.notifyAuthRequired(true);
        throw new Error('未授权或登录已过期，请重新登录');
      }

      let json: ApiResponse<T>;
      const text = await resp.text();
      try {
        json = JSON.parse(text);
      } catch {
        if (!resp.ok) {
          throw new Error(`服务请求异常 (${resp.status}): ${text.slice(0, 100)}`);
        }
        return (text as unknown) as T;
      }

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
      if (
        err.message &&
        (err.message.includes('Failed to fetch') ||
          err.message.includes('NetworkError') ||
          err.message.includes('connection refused') ||
          err.name === 'TypeError')
      ) {
        this.setConnected(false);
      }
      throw err;
    }
  }

  public setConnected(connected: boolean) {
    if (this.isConnected !== connected) {
      this.isConnected = connected;
      this.connectionListeners.forEach((listener) => {
        try {
          listener(connected);
        } catch {}
      });
    }
  }

  public onConnectionChange(listener: (connected: boolean) => void): () => void {
    this.connectionListeners.add(listener);
    try {
      listener(this.isConnected);
    } catch {}
    return () => {
      this.connectionListeners.delete(listener);
    };
  }

  public onAuthRequired(listener: (required: boolean) => void): () => void {
    this.authListeners.add(listener);
    return () => {
      this.authListeners.delete(listener);
    };
  }

  public notifyAuthRequired(required: boolean) {
    this.authListeners.forEach((listener) => {
      try {
        listener(required);
      } catch {}
    });
  }
}
