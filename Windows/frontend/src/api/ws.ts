import type { WebSocketEvent } from './types';
import { isDesktopApp } from '../utils/env';
import type { HttpTransport } from './http';

/**
 * WebSocket 事件通道：负责连接、心跳重连与事件分发。
 */
export class EventChannel {
  private ws: WebSocket | null = null;
  private reconnectTimer: any = null;
  private isConnecting = false;
  private listeners: Set<(event: WebSocketEvent) => void> = new Set();

  constructor(private transport: HttpTransport) {}

  public connect() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    if (this.isConnecting) return;
    this.isConnecting = true;

    const wsProtocol = this.transport.baseURL.startsWith('https') ? 'wss' : 'ws';
    let hostPort = this.transport.baseURL.replace(/^https?:\/\//, '');
    if (!isDesktopApp() && !localStorage.getItem('diting_ipc_custom_host') && window.location.host) {
      hostPort = window.location.host;
    }
    let wsUrl = `${wsProtocol}://${hostPort}/api/v1/events`;
    if (this.transport.token) {
      wsUrl += `?token=${encodeURIComponent(this.transport.token)}`;
    }

    try {
      this.ws = new WebSocket(wsUrl);
      this.ws.onopen = () => {
        this.isConnecting = false;
        this.transport.setConnected(true);
        this.cancelRetry();
      };

      this.ws.onmessage = (event) => {
        try {
          const parsed: WebSocketEvent = JSON.parse(event.data);
          this.listeners.forEach((listener) => listener(parsed));
        } catch (e) {
          console.error('Failed to parse WebSocket event:', e);
        }
      };

      this.ws.onclose = () => {
        this.isConnecting = false;
        this.scheduleRetry();
      };

      this.ws.onerror = () => {
        this.isConnecting = false;
        this.transport.setConnected(false);
      };
    } catch {
      this.isConnecting = false;
      this.scheduleRetry();
    }
  }

  public reconnect() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.connect();
  }

  /** 订阅事件；未连接时自动建立连接 */
  public subscribe(listener: (event: WebSocketEvent) => void): () => void {
    this.listeners.add(listener);
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      this.connect();
    }
    return () => {
      this.listeners.delete(listener);
    };
  }

  private cancelRetry() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private scheduleRetry() {
    if (!this.reconnectTimer) {
      this.reconnectTimer = setTimeout(() => {
        this.reconnectTimer = null;
        this.connect();
      }, 3000);
    }
  }
}
