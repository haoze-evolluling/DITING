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

export interface CacheConfig {
  enabled: boolean;
  maxEntries: number;
  mode: string;
  maxTtlSeconds: number;
  fixedTtlSeconds: number;
  minTtlEnabled: boolean;
  minTtlSeconds: number;
  staleFallbackEnabled: boolean;
  staleFallbackSeconds: number;
  negativeTtlEnabled: boolean;
  negativeTtlSeconds: number;
  optimistic: boolean;
  prefetchEnabled: boolean;
  prefetchThreshold: number;
  prefetchBeforeExpiryMs: number;
  excludePatterns?: string[];
  persistEnabled: boolean;
  persistPath?: string;
  persistIntervalSeconds?: number;
}

export interface CacheEntry {
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
  status: string;
  ipList?: string[];
}

export interface CacheEntriesResponse {
  total: number;
  entries: CacheEntry[];
}

export interface CacheDomainStat {
  domain: string;
  qtype: string;
  hitCount: number;
  lastHitAt: number;
}

export interface CachePersistStatus {
  path: string;
  restored?: number;
  entryCount: number;
  persistOn: boolean;
  intervalSec: number;
  lastError?: string;
  excludeRules?: string[];
  excludeHits: number;
}
