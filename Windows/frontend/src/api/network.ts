import type { LANStatusResponse, ConfigureLANRequest } from './types';
import type { HttpTransport } from './http';
import { nativeBridge } from './native';

/** 局域网 DNS 服务与防火墙放行 */
export class NetworkApi {
  constructor(private http: HttpTransport) {}

  public getLANStatus(): Promise<LANStatusResponse> {
    return this.http.request<LANStatusResponse>('/api/v1/dns/lan');
  }

  public async configureLAN(req: ConfigureLANRequest): Promise<void> {
    await this.http.request<void>('/api/v1/dns/lan/configure', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  /** 桌面端优先走 Wails 原生提权放行，Web 端回退到服务端接口 */
  public async configureFirewall(enable: boolean): Promise<string> {
    const native = await nativeBridge.configureFirewallForLAN(enable);
    if (native !== null) return native;

    const res = await this.http.request<string>('/api/v1/dns/lan/firewall', {
      method: 'POST',
      body: JSON.stringify({ enable }),
    });
    return res || (enable ? '已成功放行 53 端口防火墙规则' : '已成功移除 53 端口防火墙规则');
  }

  public async configureWebFirewall(enable: boolean): Promise<string> {
    const res = await this.http.request<string>('/api/v1/web/firewall', {
      method: 'POST',
      body: JSON.stringify({ enable }),
    });
    return res || (enable ? '已成功放行 Web 端口防火墙规则' : '已成功移除 Web 端口防火墙规则');
  }
}
