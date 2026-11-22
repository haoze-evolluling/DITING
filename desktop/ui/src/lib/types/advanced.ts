export interface SafeSearchConfig {
  enabled: boolean;
  disabled: string[];
  ttl: number;
}

export interface SafeBrowsingConfig {
  enabled: boolean;
  parentalEnabled: boolean;
  timeoutMs: number;
  cacheSize: number;
  cacheTTLSeconds: number;
}

// ---------------------------------------------------------------------------
// 加密 DNS
// ---------------------------------------------------------------------------

export interface CertConfig {
  source: string;
  certFile: string;
  keyFile: string;
  pkcs12Password: string;
  keyType: string;
  commonName: string;
  dnsNames: string[];
  ipAddresses: string[];
  validDays: number;
}

export interface ReverseProxyConfig {
  enabled: boolean;
  trustedSources: string[];
  clientIpHeader: string;
}

export interface EncryptedDNSConfig {
  enabled: boolean;
  cert: CertConfig;
  dotEnabled: boolean;
  dohEnabled: boolean;
  listenAddress: string;
  dotPort: number;
  dohPort: number;
  dohPath: string;
  serverName: string;
  ddrEnabled: boolean;
  uuid: string;
  reverseProxy: ReverseProxyConfig;
}

export interface CertInfo {
  source: string;
  subject: string;
  issuer: string;
  serialNumber: string;
  notBefore: string;
  notAfter: string;
  dnsNames: string[];
  ipAddresses: string[];
  daysRemaining: number;
  fingerprint: string;
  chainLength: number;
  loaded: boolean;
  error?: string;
  selfSigned: boolean;
}

export interface EncryptedDNSStatus {
  config: EncryptedDNSConfig;
  cert: CertInfo;
  certDir: string;
  defaultDotPort: number;
  defaultDohPort: number;
  defaultDohPath: string;
  dotListen: string;
  dohListen: string;
  dohUrls: string[];
  unrestrictedTrust: boolean;
  certExpiresSoon: boolean;
  certExpired: boolean;
}

// ---------------------------------------------------------------------------
// 域名重写与区文件
// ---------------------------------------------------------------------------

export interface RewriteRecord {
  type: string;
  value: string;
}

export interface RewriteRule {
  domain: string;
  ips?: string[];
  cname?: string;
  txt?: string[];
  ttl?: number;
  records?: RewriteRecord[];
  rcode?: string;
}

export interface RewriteConfig {
  enabled: boolean;
  ttl: number;
  rules: RewriteRule[];
}

export interface ZoneEntry {
  id: string;
  origin: string;
  content: string;
  enabled: boolean;
}

export interface ZoneState {
  id: string;
  origin: string;
  records: number;
  loaded: boolean;
  error?: string;
}

export interface ZoneConfig {
  enabled: boolean;
  ttl: number;
  zones: ZoneEntry[];
}

export interface ZoneConfigResponse extends ZoneConfig {
  states: ZoneState[];
  recordCount: number;
  maxZones: number;
  maxRecords: number;
}

export interface ZoneTestResponse {
  success: boolean;
  records: string[];
  error?: string;
}

// ---------------------------------------------------------------------------
// 安全搜索与安全浏览
// ---------------------------------------------------------------------------

export interface SafeBrowsingStats {
  cacheHits: number;
  cacheMisses: number;
  lookups: number;
  failures: number;
  blocked: number;
}

export interface SafeBrowsingResponse {
  config: SafeBrowsingConfig;
  stats: SafeBrowsingStats;
  blockingIPv4: string;
  blockingIPv6: string;
  blockMode: string;
}

// ---------------------------------------------------------------------------
// Web 远程管理
// ---------------------------------------------------------------------------

export interface WebStatus {
  enabled: boolean;
  port: number;
  listenAddress: string;
  lanAddresses: string[];
  webUrls: string[];
  firewallAllowed: boolean;
  firewallBackend: string;
  initialized: boolean;
  username: string;
}
