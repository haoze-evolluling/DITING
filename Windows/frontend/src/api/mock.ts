import type {
  StatusResponse,
  AdapterInfo,
  UpstreamInfo,
  CacheStats,
  CacheConfig,
  CacheEntriesResponse,
  CacheDomainStat,
  FilterStats,
  FilterConfig,
  FilterList,
  CheckHostResult,
  PortCheckResult,
  BootstrapConfig,
} from './types';

export const mockBootstrapConfig: BootstrapConfig = {
  enabled: true,
  servers: [
    { id: 'bs-ali', name: 'AliDNS', address: '223.5.5.5:53', weight: 1.0 },
    { id: 'bs-dnspod', name: 'DNSPod', address: '119.29.29.29:53', weight: 1.0 },
  ],
};

export const mockUpstreams: UpstreamInfo[] = [
  {
    id: 'cf-doh',
    protocol: 'DOH',
    server: '1.1.1.1',
    url: 'https://1.1.1.1/dns-query',
    active: true,
    weight: 1,
    successCount: 4210,
    failureCount: 12,
    avgLatencyMs: 14.2,
  },
  {
    id: 'google-dns',
    protocol: 'PLAIN',
    server: '8.8.8.8:53',
    active: true,
    weight: 1,
    successCount: 3820,
    failureCount: 8,
    avgLatencyMs: 22.5,
  },
  {
    id: 'quad9-dot',
    protocol: 'DOT',
    server: '9.9.9.9:853',
    active: true,
    weight: 1,
    successCount: 2910,
    failureCount: 15,
    avgLatencyMs: 28.1,
  },
];

export const mockCacheStats: CacheStats = {
  enabled: true,
  hitRatio: 0.884,
  entryCount: 1248,
  maxEntries: 4096,
  totalHits: 8940,
  totalMisses: 1180,
  staleHits: 42,
  negativeHits: 115,
  evictionCount: 0,
};

export const mockFilterStats: FilterStats = {
  enabled: true,
  activeLists: 2,
  totalRules: 12560,
  blockedQueries: 342,
  allowedQueries: 9778,
  totalQueries: 10120,
  blockRate: 3.38,
};

export const mockStatus: StatusResponse = {
  version: '0.2.0-dev',
  pid: 14280,
  uptimeSeconds: 7320,
  dns: {
    running: true,
    listenAddresses: ['127.0.0.1:53', '[::1]:53'],
    mode: 'PRIMARY_BACKUP',
    upstreams: mockUpstreams,
    bootstrap: mockBootstrapConfig,
  },
  takeover: {
    active: true,
    adapters: [
      {
        id: '{96F85E22-B91A-4C41-92A5-239FE91A4B91}',
        name: 'Wi-Fi 无线网卡',
        index: 12,
        description: 'Intel(R) Wi-Fi 6 AX201 160MHz',
        ipv4DHCP: true,
        ipv6DHCP: true,
        ipv4DNS: ['127.0.0.1', '::1'],
        ipv6DNS: [],
      },
    ],
  },
  metrics: {
    totalQueries: 10120,
    successQueries: 10095,
    failedQueries: 25,
    avgLatencyMs: 16.4,
    qps: 18.5,
  },
  cache: mockCacheStats,
  filter: mockFilterStats,
};

export const mockAdapters: AdapterInfo[] = [
  {
    id: '{96F85E22-B91A-4C41-92A5-239FE91A4B91}',
    name: 'Wi-Fi 无线网卡',
    description: 'Intel(R) Wi-Fi 6 AX201 160MHz',
    index: 12,
    status: 'Up',
    gateway: '192.168.1.1',
    ipv4DHCP: true,
    ipv6DHCP: true,
    ipv4DNS: ['127.0.0.1', '::1'],
    ipv6DNS: [],
    isPhysical: true,
  },
  {
    id: '{31D89A10-48FA-41B0-A227-6C91D5581FE2}',
    name: '以太网 (Ethernet)',
    description: 'Realtek PCIe 2.5GbE Family Controller',
    index: 8,
    status: 'Up',
    gateway: '192.168.1.1',
    ipv4DHCP: true,
    ipv6DHCP: true,
    ipv4DNS: ['192.168.1.1'],
    ipv6DNS: [],
    isPhysical: true,
  },
];

export const mockCacheConfig: CacheConfig = {
  enabled: true,
  maxEntries: 4096,
  mode: 'limit_max_ttl',
  maxTtlSeconds: 3600,
  fixedTtlSeconds: 300,
  minTtlEnabled: true,
  minTtlSeconds: 60,
  staleFallbackEnabled: true,
  staleFallbackSeconds: 300,
  negativeTtlEnabled: true,
  negativeTtlSeconds: 30,
  optimistic: true,
};

const now = Date.now();

export const mockCacheTopDomains: CacheDomainStat[] = [
  { domain: 'api.github.com', qtype: 'A', hitCount: 1420, lastHitAt: now - 12000 },
  { domain: 'www.google.com', qtype: 'A', hitCount: 980, lastHitAt: now - 25000 },
  { domain: 'login.microsoftonline.com', qtype: 'A', hitCount: 654, lastHitAt: now - 60000 },
  { domain: 'cdn.jsdelivr.net', qtype: 'AAAA', hitCount: 512, lastHitAt: now - 120000 },
  { domain: 'fonts.googleapis.com', qtype: 'A', hitCount: 430, lastHitAt: now - 300000 },
];

export const mockCacheEntries: CacheEntriesResponse = {
  total: 5,
  entries: [
    { domain: 'api.github.com', qtype: 'A', ttl: 3600, originalTtl: 3600, remainingTtl: 2840, expiresAt: now + 2840000, staleUntil: now + 3140000, hitCount: 1420, lastHitAt: now - 12000, isNegative: false, status: 'fresh', ipList: ['140.82.114.6'] },
    { domain: 'www.google.com', qtype: 'A', ttl: 300, originalTtl: 300, remainingTtl: 182, expiresAt: now + 182000, staleUntil: now + 482000, hitCount: 980, lastHitAt: now - 25000, isNegative: false, status: 'fresh', ipList: ['142.250.190.68'] },
    { domain: 'login.microsoftonline.com', qtype: 'A', ttl: 300, originalTtl: 300, remainingTtl: 45, expiresAt: now + 45000, staleUntil: now + 345000, hitCount: 654, lastHitAt: now - 60000, isNegative: false, status: 'fresh', ipList: ['20.190.177.67'] },
    { domain: 'bad-tracker.adnetwork.com', qtype: 'A', ttl: 30, originalTtl: 30, remainingTtl: 18, expiresAt: now + 18000, staleUntil: now + 18000, hitCount: 88, lastHitAt: now - 80000, isNegative: true, status: 'fresh', ipList: [] },
    { domain: 'legacy-service.local', qtype: 'AAAA', ttl: 60, originalTtl: 60, remainingTtl: 0, expiresAt: now - 1000, staleUntil: now + 299000, hitCount: 12, lastHitAt: now - 150000, isNegative: false, status: 'stale', ipList: ['fe80::1'] },
  ],
};

export const mockFilterLists: FilterList[] = [
  {
    id: 'easylist-china',
    name: 'EasyList China',
    url: 'https://filters.adtidy.org/extension/ublock/filters/224.txt',
    enabled: true,
    rulesCount: 8420,
    lastUpdated: now - 14400000,
  },
  {
    id: 'adguard-dns',
    name: 'AdGuard DNS Filter',
    url: 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt',
    enabled: true,
    rulesCount: 4140,
    lastUpdated: now - 43200000,
  },
];

export const mockFilterConfig: FilterConfig = {
  enabled: true,
  blockMode: 'null_ip',
  blockingIPv4: '0.0.0.0',
  blockingIPv6: '::',
  customRules: ['||tracking.example.com^', '0.0.0.0 telemetry.ads.com', '@@||safe-site.com^'],
  lists: mockFilterLists,
  updateIntervalHours: 24,
};

export function handleMockRequest(rawPath: string, _options: RequestInit = {}): any {
  const path = rawPath.split('?')[0];
  if (path === '/api/v1/status') return mockStatus;
  if (path === '/api/v1/health') return 'OK';
  if (path === '/api/v1/adapters') return mockAdapters;
  if (path === '/api/v1/upstreams') return mockUpstreams;
  if (path === '/api/v1/upstreams/test' || path === '/api/v1/upstream/test') return { success: true, server: '1.1.1.1', rttMs: 14.8, latencyMs: 14.8, error: '' };
  if (path === '/api/v1/upstream/configure') return { success: true };
  if (path === '/api/v1/bootstrap/configure') return { success: true };
  if (path === '/api/v1/cache/stats') return mockCacheStats;
  if (path === '/api/v1/cache/config') return mockCacheConfig;
  if (path === '/api/v1/cache/top') return mockCacheTopDomains;
  if (path === '/api/v1/cache/entries') return mockCacheEntries;
  if (path === '/api/v1/filter/stats') return mockFilterStats;
  if (path === '/api/v1/filter/config') return mockFilterConfig;
  if (path === '/api/v1/filter/lists') return { total: mockFilterLists.length, lists: mockFilterLists };
  if (path === '/api/v1/filter/custom') return mockFilterConfig.customRules;
  if (path === '/api/v1/filter/check') {
    return {
      blocked: true,
      action: 'block',
      matchedRule: '||adservice.google.com^',
      listName: 'AdGuard DNS Filter',
      reason: '命中广告拦截规则',
    } as CheckHostResult;
  }
  if (path === '/api/v1/portcheck' || path === '/api/v1/system/check-port') {
    return {
      available: true,
      hasICS: false,
      diagnostic: 'DNS 端口 (53) 正常空闲，未检测到网络共享或第三方软件占用冲突。',
      conflicts: [],
    } as PortCheckResult;
  }
  return { success: true };
}
