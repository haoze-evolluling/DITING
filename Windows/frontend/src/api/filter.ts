import type { FilterStats, FilterConfig, FilterList, CheckHostResult } from './types';
import type { HttpTransport } from './http';

/** 规则拦截（过滤引擎、订阅列表与自定义规则） */
export class FilterApi {
  constructor(private http: HttpTransport) {}

  public getStats(): Promise<FilterStats> {
    return this.http.request<FilterStats>('/api/v1/filter/stats');
  }

  public getConfig(): Promise<FilterConfig> {
    return this.http.request<FilterConfig>('/api/v1/filter/config');
  }

  public async updateConfig(config: Partial<FilterConfig>): Promise<void> {
    await this.http.request<void>('/api/v1/filter/config', {
      method: 'POST',
      body: JSON.stringify(config),
    });
  }

  public async getLists(): Promise<FilterList[]> {
    const res = await this.http.request<{ total: number; lists: FilterList[] }>('/api/v1/filter/lists');
    return res?.lists || [];
  }

  public async addList(list: Partial<FilterList>): Promise<void> {
    await this.http.request<void>('/api/v1/filter/lists/add', {
      method: 'POST',
      body: JSON.stringify(list),
    });
  }

  public async updateList(list: FilterList): Promise<void> {
    await this.http.request<void>('/api/v1/filter/lists/update', {
      method: 'POST',
      body: JSON.stringify(list),
    });
  }

  public async deleteList(id: string): Promise<void> {
    await this.http.request<void>('/api/v1/filter/lists/delete', {
      method: 'POST',
      body: JSON.stringify({ id }),
    });
  }

  public async refreshLists(id = ''): Promise<void> {
    await this.http.request<void>('/api/v1/filter/lists/refresh', {
      method: 'POST',
      body: JSON.stringify({ id }),
    });
  }

  public async getCustomRules(): Promise<string[]> {
    const res = await this.http.request<{ rules: string[] }>('/api/v1/filter/rules');
    return res?.rules || [];
  }

  public async setCustomRules(rules: string[]): Promise<void> {
    await this.http.request<void>('/api/v1/filter/rules', {
      method: 'POST',
      body: JSON.stringify({ rules }),
    });
  }

  public checkHost(domain: string, qtype: string | number = 'A'): Promise<CheckHostResult> {
    return this.http.request<CheckHostResult>('/api/v1/filter/check', {
      method: 'POST',
      body: JSON.stringify({ domain, qtype: String(qtype) }),
    });
  }
}
