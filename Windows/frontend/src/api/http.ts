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
    if (!isDesktopApp()) {
      localStorage.setItem('diting_ipc_custom_host', host);
      localStorage.setItem('diting_ipc_custom_port', port);
    }
    localStorage.setItem('diting_ipc_host', host);
    localStorage.setItem('diting_ipc_port', port);
    localStorage.setItem('diting_ipc_token', token);
    this.baseURL = `http://${host}:${port}`;
    this.token = token;
  }

  public getConfig() {
    let defHost = '127.0.0.1';
    let defPort = '15353';
    if (!isDesktopApp() && window.location.hostname) {
      defHost = window.location.hostname;
      defPort = window.location.port || (window.location.protocol === 'https:' ? '443' : '80');
    }
    return {
      host: localStorage.getItem('diting_ipc_custom_host') || localStorage.getItem('diting_ipc_host') || defHost,
      port: localStorage.getItem('diting_ipc_custom_port') || localStorage.getItem('diting_ipc_port') || defPort,
      token: this.token,
    };
  }

  public setSession(token: string) {
    this.token = token;
    localStorage.setItem('diting_session_token', token);
  }

  public clearSession() {
    this.token = '';
    localStorage.removeItem('diting_session_token');
    localStorage.removeItem('diting_session_user');
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
      this.connectionListeners.forEach((listener) => listener(connected));
    }
  }

  public onConnectionChange(listener: (connected: boolean) => void): () => void {
    this.connectionListeners.add(listener);
    listener(this.isConnected);
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
    this.authListeners.forEach((listener) => listener(required));
  }
}
