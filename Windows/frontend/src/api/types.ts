export interface ApiResponse<T = any> {
  success: boolean;
  message?: string;
  data?: T;
  error?: string;
  conflict?: PortCheckResult;
}

export interface UpstreamInfo {
  id: string;
  protocol: 'PLAIN' | 'DOH' | 'DOT';
  server: string;
  url?: string;
  weight?: number;
  active: boolean;
  successCount: number;
  failureCount: number;
  avgLatencyMs: number;
}

export interface DNSStatus {
  running: boolean;
  listenAddresses: string[];
  mode: string;
  upstreams: UpstreamInfo[];
}

export interface AdapterState {
  id: string;
  name: string;
  index: number;
  description: string;
  ipv4DHCP: boolean;
  ipv6DHCP: boolean;
  ipv4DNS: string[];
  ipv6DNS: string[];
}

export interface TakeoverStatus {
  active: boolean;
  adapters: AdapterState[];
}

export interface MetricsStatus {
  totalQueries: number;
  successQueries: number;
  failedQueries: number;
  avgLatencyMs: number;
  qps: number;
}

export interface StatusResponse {
  version: string;
  pid: number;
  uptimeSeconds: number;
  dns: DNSStatus;
  takeover: TakeoverStatus;
  metrics: MetricsStatus;
  cache?: CacheStats;
  filter?: FilterStats;
}

export interface CacheStats {
  enabled: boolean;
  totalHits: number;
  totalMisses: number;
  staleHits: number;
  negativeHits: number;
  hitRatio: number;
  entryCount: number;
  maxEntries: number;
  evictionCount: number;
}

export interface CacheConfig {
  enabled: boolean;
  maxEntries: number;
  mode: 'follow_dns_ttl' | 'limit_max_ttl' | 'fixed_ttl' | string;
  maxTtlSeconds: number;
  fixedTtlSeconds: number;
  minTtlEnabled: boolean;
  minTtlSeconds: number;
  staleFallbackEnabled: boolean;
  staleFallbackSeconds: number;
  negativeTtlEnabled: boolean;
  negativeTtlSeconds: number;
  optimistic: boolean;
}

export interface CacheEntryItem {
  domain: string;
  qtype: string;
  ttl: number;
  originalTtl: number;
  remainingTtl: number;
  expiresAt: number;
  staleUntil: number;
  hitCount: number;
  lastHitAt: number;
  isNegative: boolean;
  status: 'fresh' | 'stale';
  ipList?: string[];
}

export interface CacheEntriesResponse {
  total: number;
  entries: CacheEntryItem[];
}

export interface CacheDomainStat {
  domain: string;
  qtype: string;
  hitCount: number;
  lastHitAt: number;
}

export interface AdapterInfo {
  id: string;
  name: string;
  description: string;
  index: number;
  status: string;
  gateway: string;
  ipv4DHCP: boolean;
  ipv6DHCP: boolean;
  ipv4DNS: string[];
  ipv6DNS: string[];
  isPhysical: boolean;
}

export interface PortConflictInfo {
  port?: number;
  protocol: string;
  localAddress: string;
  pid: number;
  processName: string;
  serviceName?: string;
  isICS: boolean;
  isSelf: boolean;
  diagnosis?: string;
}

export interface PortCheckResult {
  available: boolean;
  hasICS: boolean;
  diagnostic: string;
  conflicts: PortConflictInfo[];
}

export interface QueryEventData {
  domain: string;
  qtype: string;
  clientIP: string;
  durationMs: number;
  success: boolean;
  rcode?: string;
  cacheHit?: string;
  blocked?: boolean;
  filterRule?: string;
  filterReason?: string;
  errorMessage?: string;
}

export interface FilterStats {
  enabled: boolean;
  totalRules: number;
  activeLists: number;
  totalQueries: number;
  blockedQueries: number;
  allowedQueries: number;
  blockRate: number;
}

export interface FilterList {
  id: string;
  name: string;
  url: string;
  enabled: boolean;
  rulesCount: number;
  lastUpdated: number;
  checksum?: string;
}

export interface FilterConfig {
  enabled: boolean;
  blockMode: 'null_ip' | 'nxdomain' | 'refused' | string;
  blockingIPv4: string;
  blockingIPv6: string;
  customRules: string[];
  lists: FilterList[];
  updateIntervalHours: number;
  dataDir?: string;
}

export interface CheckHostResult {
  blocked: boolean;
  action: 'block' | 'allow' | 'pass' | string;
  matchedRule?: string;
  listName?: string;
  reason?: string;
}

export interface WebSocketEvent {
  type: 'query' | 'metrics' | 'takeover' | 'dns' | 'alert' | 'upstream';
  timestamp: number;
  data: any;
}

export interface ProviderConfig {
  id: string;
  protocol: 'PLAIN' | 'DOH' | 'DOT';
  server: string;
  url?: string;
  weight?: number;
}

export interface UpstreamConfigureRequest {
  mode: string;
  providers: ProviderConfig[];
}

export interface TestUpstreamRequest {
  protocol: string;
  server: string;
  url?: string;
}

export interface TestUpstreamResponse {
  success: boolean;
  latencyMs: number;
  error?: string;
}

export interface CoreServiceStatus {
  installed: boolean;
  running: boolean;
  state: 'running' | 'stopped' | 'not_installed' | 'start_pending' | 'stop_pending' | 'unknown' | string;
  stateText: string;
  executablePath: string;
  isElevated: boolean;
  canInstall: boolean;
  message?: string;
}

