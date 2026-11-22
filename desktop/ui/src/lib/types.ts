export interface ApiEnvelope<T> {
  success: boolean;
  message?: string;
  data?: T;
  error?: string;
  conflict?: unknown;
}

export interface AuthStatus {
  initialized: boolean;
  webEnabled: boolean;
  authenticated: boolean;
  username: string;
  locked: boolean;
  lockoutRemainingSec: number;
}

export interface LoginResult {
  token: string;
  username: string;
  expiresAt: number;
}

export interface MetaInfo {
  os: string;
}

export interface UpstreamInfo {
  id: string;
  protocol: string;
  server: string;
  url?: string;
  weight: number;
  active: boolean;
  successCount: number;
  failureCount: number;
  avgLatencyMs: number;
  pinSet?: boolean;
}

export interface BootstrapServer {
  id: string;
  name: string;
  address: string;
  weight: number;
}

export interface BootstrapConfig {
  enabled: boolean;
  servers: BootstrapServer[];
}

export interface DnsStatus {
  running: boolean;
  listenAddresses: string[];
  allowLAN: boolean;
  lanAddresses?: string[];
  mode: string;
  upstreams: UpstreamInfo[];
  bootstrap: BootstrapConfig;
  enableEDE: boolean;
  blockUnqualified: boolean;
  blockPrivatePTR: boolean;
  blockIPv6: boolean;
  blockECH: boolean;
  ednsPadding: number;
  blockANY: boolean;
  blockANYMode: string;
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
  prefetchCount: number;
}

export interface FilterStats {
  enabled: boolean;
  totalRules: number;
  activeLists: number;
  totalQueries: number;
  blockedQueries: number;
  allowedQueries: number;
  blockRate: number;
  scheduleActive: boolean;
  paused: boolean;
  pausedRemainingSec: number;
  pausedUntilMs: number;
}

export interface ClientSummary {
  ip: string;
  name: string;
  queryCount: number;
  lastSeen: number;
}

export interface StatusResponse {
  version: string;
  pid: number;
  uptimeSeconds: number;
  dns: DnsStatus;
  takeover: TakeoverStatus;
  metrics: MetricsStatus;
  cache: CacheStats;
  filter: FilterStats;
  clients?: ClientSummary[];
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
  hasResidualLoopback: boolean;
}

export interface AutoStartStatus {
  enabled: boolean;
  mechanism: string;
  detail: string;
}

export interface ServiceStatus {
  installed: boolean;
  running: boolean;
  state: string;
  stateText: string;
  executablePath: string;
  isElevated: boolean;
  canInstall: boolean;
  message: string;
  autoStart?: AutoStartStatus;
}

export interface PortConflict {
  port: number;
  protocol: string;
  localAddress: string;
  pid: number;
  processName: string;
  serviceName?: string;
  isICS: boolean;
  isSelf: boolean;
  diagnosis: string;
}

export interface PortCheckResult {
  available: boolean;
  conflicts: PortConflict[];
  hasICS: boolean;
  canAutofix: boolean;
  diagnostic: string;
}

export interface EmergencyRestoreResult {
  healed: boolean;
  message: string;
}

export type QueryStatus = "allowed" | "blocked" | "cached" | "stale" | "error";

export interface QueryRecord {
  ts: number;
  domain: string;
  qtype?: string;
  clientIP?: string;
  clientName?: string;
  durationMs: number;
  rcode?: string;
  status: QueryStatus | string;
  cached?: boolean;
  ttl?: number;
  cacheHit?: string;
  blocked?: boolean;
  filterRule?: string;
  filterReason?: string;
  protocol?: string;
  upstreamProvider?: string;
  error?: string;
}

export interface QueryEvent {
  domain: string;
  qtype: string;
  clientIP: string;
  clientName?: string;
  durationMs: number;
  success: boolean;
  rcode?: string;
  cacheHit?: string;
  blocked: boolean;
  filterRule?: string;
  filterReason?: string;
  errorMessage?: string;
}

export interface QuerySummary {
  queries: number;
  blocked: number;
  cached: number;
  forwarded: number;
  errors: number;
  avgResponseMs: number;
  cacheHitRate: number;
}

export interface HourPoint {
  hourMs: number;
  queries: number;
  blocked: number;
  cached: number;
}

export interface NameCount {
  name: string;
  count: number;
}

export interface QueryLogStats {
  summary: QuerySummary;
  perHour: HourPoint[];
  topDomains: NameCount[];
  topBlocked: NameCount[];
  topClients: NameCount[];
}

export interface QuerySearchResult {
  total: number;
  entries: QueryRecord[];
}

export interface QueryLogConfig {
  enabled: boolean;
  maxEntries: number;
  fileEnabled: boolean;
  retentionDays: number;
  logClients: boolean;
  dataDir: string;
}

export interface QuerySearchParams {
  domain?: string;
  client?: string;
  qtype?: string;
  status?: string;
  startMs?: number;
  endMs?: number;
  limit?: number;
  offset?: number;
}

export interface StreamEvent<T = unknown> {
  type: "query" | "metrics" | "dns" | "takeover" | string;
  timestamp: number;
  data: T;
}
