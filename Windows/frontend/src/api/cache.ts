import type { CacheStats, CacheConfig, CacheEntriesResponse, CacheDomainStat } from './types';
import type { HttpTransport } from './http';

/** 智能解析缓存 */
export class CacheApi {
  constructor(private http: HttpTransport) {}

  public getStats(): Promise<CacheStats> {
    return this.http.request<CacheStats>('/api/v1/cache/stats');
  }

  public getEntries(query = '', limit = 50): Promise<CacheEntriesResponse> {
    const params = new URLSearchParams();
    if (query) params.set('q', query);
    if (limit) params.set('limit', limit.toString());
    return this.http.request<CacheEntriesResponse>(`/api/v1/cache/entries?${params.toString()}`);
  }

  public getTopDomains(limit = 10): Promise<CacheDomainStat[]> {
    return this.http.request<CacheDomainStat[]>(`/api/v1/cache/top?limit=${limit}`);
  }

  public async clear(): Promise<void> {
    await this.http.request<void>('/api/v1/cache/clear', { method: 'POST' });
  }

  public getConfig(): Promise<CacheConfig> {
    return this.http.request<CacheConfig>('/api/v1/cache/config');
  }

  public async updateConfig(config: CacheConfig): Promise<void> {
    await this.http.request<void>('/api/v1/cache/config', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }
}
