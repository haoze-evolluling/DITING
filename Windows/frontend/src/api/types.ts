export interface ApiResponse<T = any> {
  success: boolean;
  message?: string;
  data?: T;
  error?: string;
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
  protocol: string;
  localAddress: string;
  pid: number;
  processName: string;
  isICS: boolean;
  isSelf: boolean;
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
  errorMessage?: string;
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
