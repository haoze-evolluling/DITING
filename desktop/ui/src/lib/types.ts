import type { CacheStats } from "./types/cache";
import type {
  RewriteConfig,
  SafeBrowsingConfig,
  SafeSearchConfig,
  ZoneConfig,
} from "./types/advanced";

export * from "./types/cache";
export * from "./types/advanced";
export * from "./types/openwrt";

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
  platformKind?: string;
  distro?: string | null;
  storageBackend?: string;
  databasePath?: string | null;
  queryLogPath?: string | null;
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

export interface ClientGroup {
  id: string;
  name: string;
  enabled: boolean;
  clients: string[];
  ruleListIds?: string[];
  blockMode?: string;
  upstreamIds?: string[];
  scheduleEnabled?: boolean;
  schedules?: BlockingSchedule[];
  allowlistOnly?: boolean;
}

export interface ClientGroupRuleListOption {
  id: string;
  name: string;
  enabled: boolean;
}

export interface ClientGroupUpstreamOption {
  id: string;
  protocol: string;
  server: string;
}

export interface ClientGroupConfigResponse {
  enabled: boolean;
  groups: ClientGroup[];
  ruleLists: ClientGroupRuleListOption[];
  upstreams: ClientGroupUpstreamOption[];
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
  hosts?: HostsConfig;
  rebind?: RebindConfig;
  access?: AccessControlConfig;
  rateLimit?: RateLimitConfig;
  dns64?: DNS64Config;
  ecs?: ECSConfig;
  safeSearch?: SafeSearchConfig;
  safeBrowsing?: SafeBrowsingConfig;
  rewrite?: RewriteConfig;
  zone?: ZoneConfig;
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

// ---------------------------------------------------------------------------
// 上游解析
// ---------------------------------------------------------------------------

export interface ProviderConfig {
  id: string;
  protocol: string;
  server: string;
  url: string;
  weight?: number;
  pin?: string;
}

export interface ResolverConfig {
  mode: string;
  providers: ProviderConfig[];
  bootstrap: BootstrapConfig;
  conditionalRoutes?: Record<string, string>;
  ednsPadding?: number;
  fallbackProviders?: ProviderConfig[];
  fallbackTimeoutMs?: number;
  fallbackOnRcode?: number[] | null;
  fallbackOnError?: boolean | null;
}

export interface UpstreamTestResult {
  success: boolean;
  latencyMs: number;
  error?: string;
}

export interface StampParseResult {
  protocol: string;
  server: string;
  url: string;
  providerName?: string;
  path?: string;
  serverAddr?: string;
  bootstrapIps?: string[];
  pin?: string;
  protoName?: string;
}

// ---------------------------------------------------------------------------
// 规则与拦截
// ---------------------------------------------------------------------------

export interface BlockingSchedule {
  id: string;
  name: string;
  enabled: boolean;
  weekdays: string[];
  start: string;
  end: string;
}

export interface FilterList {
  id: string;
  name: string;
  url: string;
  enabled: boolean;
  rulesCount: number;
  lastUpdated: number;
  checksum?: string;
  etag?: string;
  lastModified?: string;
  lastStatus?: string;
  lastError?: string;
}

export interface FilterConfig {
  enabled: boolean;
  blockMode: string;
  blockingIPv4: string;
  blockingIPv6: string;
  customRules: string[];
  lists: FilterList[];
  updateIntervalHours: number;
  dataDir: string;
  scheduleEnabled: boolean;
  schedules: BlockingSchedule[];
  filterResponse: boolean;
  allowlistOnly: boolean;
  bogusNxDomain: boolean;
  bogusNxDomainNetworks: string[];
  blockedServices: string[];
  blockedServiceGroups: string[];
  serviceSchedules: Record<string, BlockingSchedule[]>;
}

export interface FilterListsResponse {
  total: number;
  lists: FilterList[];
}

export interface FilterRulesResponse {
  rules: string[];
}

export interface ScheduleConfigResponse {
  enabled: boolean;
  schedules: BlockingSchedule[];
  active: boolean;
  activeId: string;
}

export interface FilterPauseResponse {
  paused: boolean;
  remainingSeconds: number;
  pausedUntilMs: number;
  blockingEnabled: boolean;
}

export interface BlockedService {
  id: string;
  name: string;
  group: string;
  rules: string[];
  ruleCount: number;
  source: string;
}

export interface BlockedServiceGroup {
  id: string;
  name: string;
  count: number;
}

export interface ServiceScheduleState {
  serviceId: string;
  active: boolean;
  hasSchedule: boolean;
  activeName?: string;
}

export interface BlockedServicesResponse {
  services: BlockedService[];
  groups: BlockedServiceGroup[];
  blockedIds: string[];
  blockedGroups: string[];
  activeRules: number;
  schedules: Record<string, BlockingSchedule[]>;
  scheduleStates: ServiceScheduleState[];
}

export interface CheckHostResult {
  blocked: boolean;
  action: string;
  matchedRule: string;
  listName: string;
  reason: string;
  rewritten?: {
    rcode: number;
    records: { type: string; value: string; ttl: number }[];
    summary: string[];
  };
}

// ---------------------------------------------------------------------------
// 局域网与客户端
// ---------------------------------------------------------------------------

export interface LanStatus {
  allowLAN: boolean;
  listenAddresses: string[];
  lanAddresses: string[];
  firewallAllowed: boolean;
  firewallBackend: string;
}

export interface AccessControlConfig {
  allowedClients: string[];
  blockedClients: string[];
}

export interface RateLimitConfig {
  enabled: boolean;
  rate: number;
  burst: number;
  ipv4Prefix: number;
  ipv6Prefix: number;
  exemptIPs: string[];
}

export interface HostsConfig {
  enabled: boolean;
  useSystemHost: boolean;
  customFiles: string[];
  ttl: number;
}

export interface RebindConfig {
  enabled: boolean;
  allowedDomains: string[];
}

export interface DNS64Config {
  enabled: boolean;
  prefixes: string[];
}

export interface ECSConfig {
  enabled: boolean;
  stripECS: boolean;
  customSubnet: string;
}
