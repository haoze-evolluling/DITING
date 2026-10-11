import type {
  StatusResponse,
  AdapterInfo,
  PortCheckResult,
  UpstreamConfigureRequest,
  TestUpstreamRequest,
  TestUpstreamResponse,
  BootstrapConfig,
} from './types';
import type { HttpTransport } from './http';

/** 核心网络与 DNS 状态、网卡接管、端口诊断与上游配置 */
export class CoreApi {
  constructor(private http: HttpTransport) {}

  public getStatus(): Promise<StatusResponse> {
    return this.http.request<StatusResponse>('/api/v1/status');
  }

  public async startDNS(): Promise<void> {
    await this.http.request<void>('/api/v1/dns/start', { method: 'POST' });
  }

  public async stopDNS(): Promise<void> {
    await this.http.request<void>('/api/v1/dns/stop', { method: 'POST' });
  }

  public async checkHealth(): Promise<boolean> {
    try {
      const res = await this.http.request<string>('/api/v1/health');
      return res === 'ok' || Boolean(res);
    } catch {
      return false;
    }
  }

  public async enableTakeover(): Promise<void> {
    await this.http.request<void>('/api/v1/takeover/enable', { method: 'POST' });
  }

  public async disableTakeover(): Promise<void> {
    await this.http.request<void>('/api/v1/takeover/disable', { method: 'POST' });
  }

  public getAdapters(): Promise<AdapterInfo[]> {
    return this.http.request<AdapterInfo[]>('/api/v1/adapters');
  }

  public async setAdapterTakeover(adapterId: string, enable: boolean): Promise<void> {
    await this.http.request<void>('/api/v1/takeover/adapter', {
      method: 'POST',
      body: JSON.stringify({ adapterId, enable }),
    });
  }

  public checkPortConflicts(): Promise<PortCheckResult> {
    return this.http.request<PortCheckResult>('/api/v1/portcheck');
  }

  public autofixPortConflicts(startDNS = false): Promise<PortCheckResult> {
    return this.http.request<PortCheckResult>('/api/v1/portcheck/autofix', {
      method: 'POST',
      body: JSON.stringify({ startDNS }),
    });
  }

  public async configureUpstream(req: UpstreamConfigureRequest): Promise<void> {
    await this.http.request<void>('/api/v1/upstream/configure', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public testUpstream(req: TestUpstreamRequest): Promise<TestUpstreamResponse> {
    return this.http.request<TestUpstreamResponse>('/api/v1/upstream/test', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  public async configureBootstrap(config: BootstrapConfig): Promise<void> {
    await this.http.request<void>('/api/v1/bootstrap/configure', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }
}
