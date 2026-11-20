library;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

double _double(Object? value) => switch (value) {
  num() => value.toDouble(),
  String() => double.tryParse(value) ?? 0,
  _ => 0,
};

bool _bool(Object? value) => value == true;

String _string(Object? value) => value == null ? '' : '$value';

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

const List<String> desktopCacheModes = [
  'limit_max_ttl',
  'follow_dns_ttl',
  'fixed_ttl',
];

const int desktopCacheDefaultPersistSeconds = 300;

class DesktopCacheStats {
  const DesktopCacheStats({
    required this.enabled,
    required this.hits,
    required this.misses,
    required this.staleHits,
    required this.negativeHits,
    required this.hitRatio,
    required this.entryCount,
    required this.maxEntries,
    required this.evictions,
    required this.prefetchCount,
  });

  static const empty = DesktopCacheStats(
    enabled: false,
    hits: 0,
    misses: 0,
    staleHits: 0,
    negativeHits: 0,
    hitRatio: 0,
    entryCount: 0,
    maxEntries: 0,
    evictions: 0,
    prefetchCount: 0,
  );

  factory DesktopCacheStats.fromJson(Map<String, Object?> json) =>
      DesktopCacheStats(
        enabled: _bool(json['enabled']),
        hits: _int(json['totalHits']),
        misses: _int(json['totalMisses']),
        staleHits: _int(json['staleHits']),
        negativeHits: _int(json['negativeHits']),
        hitRatio: _double(json['hitRatio']),
        entryCount: _int(json['entryCount']),
        maxEntries: _int(json['maxEntries']),
        evictions: _int(json['evictionCount']),
        prefetchCount: _int(json['prefetchCount']),
      );

  final bool enabled;
  final int hits;
  final int misses;
  final int staleHits;
  final int negativeHits;

  final double hitRatio;
  final int entryCount;
  final int maxEntries;
  final int evictions;
  final int prefetchCount;

  double get fill =>
      maxEntries <= 0 ? 0 : (entryCount / maxEntries).clamp(0, 1).toDouble();
}

class DesktopCacheEntry {
  const DesktopCacheEntry({
    required this.domain,
    required this.qtype,
    required this.originalTtl,
    required this.remainingTtl,
    required this.hitCount,
    required this.isNegative,
    required this.status,
    required this.ipList,
  });

  factory DesktopCacheEntry.fromJson(Map<String, Object?> json) =>
      DesktopCacheEntry(
        domain: _string(json['domain']),
        qtype: _string(json['qtype']),
        originalTtl: _int(json['originalTtl']),
        remainingTtl: _int(json['remainingTtl']),
        hitCount: _int(json['hitCount']),
        isNegative: _bool(json['isNegative']),
        status: _string(json['status']),
        ipList: _strings(json['ipList']),
      );

  final String domain;
  final String qtype;
  final int originalTtl;

  final int remainingTtl;
  final int hitCount;
  final bool isNegative;

  final String status;
  final List<String> ipList;

  bool get isStale => status == 'stale';
}

class DesktopCacheEntries {
  const DesktopCacheEntries({required this.total, required this.entries});

  static const empty = DesktopCacheEntries(total: 0, entries: []);

  factory DesktopCacheEntries.fromJson(Map<String, Object?> json) =>
      DesktopCacheEntries(
        total: _int(json['total']),
        entries: [
          for (final item in json['entries'] as List? ?? const [])
            if (item is Map)
              DesktopCacheEntry.fromJson(item.cast<String, Object?>()),
        ],
      );

  final int total;
  final List<DesktopCacheEntry> entries;
}

class DesktopCacheDomain {
  const DesktopCacheDomain({
    required this.domain,
    required this.qtype,
    required this.hitCount,
    required this.lastHitAt,
  });

  factory DesktopCacheDomain.fromJson(Map<String, Object?> json) =>
      DesktopCacheDomain(
        domain: _string(json['domain']),
        qtype: _string(json['qtype']),
        hitCount: _int(json['hitCount']),
        lastHitAt: _int(json['lastHitAt']),
      );

  final String domain;
  final String qtype;
  final int hitCount;

  final int lastHitAt;
}

List<DesktopCacheDomain> desktopCacheDomains(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is Map) DesktopCacheDomain.fromJson(item.cast<String, Object?>()),
];

class DesktopCachePersist {
  const DesktopCachePersist({
    required this.path,
    required this.restored,
    required this.entryCount,
    required this.persistOn,
    required this.intervalSec,
    required this.lastError,
    required this.excludeHits,
  });

  factory DesktopCachePersist.fromJson(Map<String, Object?> json) =>
      DesktopCachePersist(
        path: _string(json['path']),
        restored: _int(json['restored']),
        entryCount: _int(json['entryCount']),
        persistOn: _bool(json['persistOn']),
        intervalSec: _int(json['intervalSec']),
        lastError: _string(json['lastError']),
        excludeHits: _int(json['excludeHits']),
      );

  final String path;

  final int restored;
  final int entryCount;
  final bool persistOn;
  final int intervalSec;

  final String lastError;
  final int excludeHits;
}

class DesktopCacheConfig {
  const DesktopCacheConfig({
    required this.enabled,
    required this.maxEntries,
    required this.mode,
    required this.maxTtlSeconds,
    required this.fixedTtlSeconds,
    required this.minTtlEnabled,
    required this.minTtlSeconds,
    required this.staleFallbackEnabled,
    required this.staleFallbackSeconds,
    required this.negativeTtlEnabled,
    required this.negativeTtlSeconds,
    required this.optimistic,
    required this.prefetchEnabled,
    required this.prefetchThreshold,
    required this.prefetchBeforeExpiryMs,
    required this.excludePatterns,
    required this.persistEnabled,
    required this.persistPath,
    required this.persistIntervalSeconds,
  });

  static const defaults = DesktopCacheConfig(
    enabled: true,
    maxEntries: 4096,
    mode: 'limit_max_ttl',
    maxTtlSeconds: 3600,
    fixedTtlSeconds: 3600,
    minTtlEnabled: true,
    minTtlSeconds: 60,
    staleFallbackEnabled: true,
    staleFallbackSeconds: 300,
    negativeTtlEnabled: true,
    negativeTtlSeconds: 30,
    optimistic: true,
    prefetchEnabled: false,
    prefetchThreshold: 5,
    prefetchBeforeExpiryMs: 30000,
    excludePatterns: [],
    persistEnabled: false,
    persistPath: '',
    persistIntervalSeconds: desktopCacheDefaultPersistSeconds,
  );

  factory DesktopCacheConfig.fromJson(Map<String, Object?> json) {
    const fallback = defaults;
    return DesktopCacheConfig(
      enabled: _bool(json['enabled']),
      maxEntries: _int(json['maxEntries']),
      mode: _string(json['mode']).isEmpty
          ? fallback.mode
          : _string(json['mode']),
      maxTtlSeconds: _int(json['maxTtlSeconds']),
      fixedTtlSeconds: _int(json['fixedTtlSeconds']),
      minTtlEnabled: _bool(json['minTtlEnabled']),
      minTtlSeconds: _int(json['minTtlSeconds']),
      staleFallbackEnabled: _bool(json['staleFallbackEnabled']),
      staleFallbackSeconds: _int(json['staleFallbackSeconds']),
      negativeTtlEnabled: _bool(json['negativeTtlEnabled']),
      negativeTtlSeconds: _int(json['negativeTtlSeconds']),
      optimistic: _bool(json['optimistic']),
      prefetchEnabled: _bool(json['prefetchEnabled']),
      prefetchThreshold: _int(json['prefetchThreshold']),
      prefetchBeforeExpiryMs: _int(json['prefetchBeforeExpiryMs']),
      excludePatterns: _strings(json['excludePatterns']),
      persistEnabled: _bool(json['persistEnabled']),
      persistPath: _string(json['persistPath']),
      persistIntervalSeconds: _int(json['persistIntervalSeconds']),
    );
  }

  final bool enabled;

  final int maxEntries;

  final String mode;
  final int maxTtlSeconds;
  final int fixedTtlSeconds;
  final bool minTtlEnabled;
  final int minTtlSeconds;
  final bool staleFallbackEnabled;
  final int staleFallbackSeconds;
  final bool negativeTtlEnabled;
  final int negativeTtlSeconds;

  final bool optimistic;
  final bool prefetchEnabled;
  final int prefetchThreshold;
  final int prefetchBeforeExpiryMs;

  final List<String> excludePatterns;
  final bool persistEnabled;

  final String persistPath;
  final int persistIntervalSeconds;

  int get effectivePersistIntervalSeconds => persistIntervalSeconds <= 0
      ? desktopCacheDefaultPersistSeconds
      : persistIntervalSeconds;

  DesktopCacheConfig copyWith({
    bool? enabled,
    int? maxEntries,
    String? mode,
    int? maxTtlSeconds,
    int? fixedTtlSeconds,
    bool? minTtlEnabled,
    int? minTtlSeconds,
    bool? staleFallbackEnabled,
    int? staleFallbackSeconds,
    bool? negativeTtlEnabled,
    int? negativeTtlSeconds,
    bool? optimistic,
    bool? prefetchEnabled,
    int? prefetchThreshold,
    int? prefetchBeforeExpiryMs,
    List<String>? excludePatterns,
    bool? persistEnabled,
    String? persistPath,
    int? persistIntervalSeconds,
  }) => DesktopCacheConfig(
    enabled: enabled ?? this.enabled,
    maxEntries: maxEntries ?? this.maxEntries,
    mode: mode ?? this.mode,
    maxTtlSeconds: maxTtlSeconds ?? this.maxTtlSeconds,
    fixedTtlSeconds: fixedTtlSeconds ?? this.fixedTtlSeconds,
    minTtlEnabled: minTtlEnabled ?? this.minTtlEnabled,
    minTtlSeconds: minTtlSeconds ?? this.minTtlSeconds,
    staleFallbackEnabled: staleFallbackEnabled ?? this.staleFallbackEnabled,
    staleFallbackSeconds: staleFallbackSeconds ?? this.staleFallbackSeconds,
    negativeTtlEnabled: negativeTtlEnabled ?? this.negativeTtlEnabled,
    negativeTtlSeconds: negativeTtlSeconds ?? this.negativeTtlSeconds,
    optimistic: optimistic ?? this.optimistic,
    prefetchEnabled: prefetchEnabled ?? this.prefetchEnabled,
    prefetchThreshold: prefetchThreshold ?? this.prefetchThreshold,
    prefetchBeforeExpiryMs:
        prefetchBeforeExpiryMs ?? this.prefetchBeforeExpiryMs,
    excludePatterns: excludePatterns ?? this.excludePatterns,
    persistEnabled: persistEnabled ?? this.persistEnabled,
    persistPath: persistPath ?? this.persistPath,
    persistIntervalSeconds:
        persistIntervalSeconds ?? this.persistIntervalSeconds,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'maxEntries': maxEntries,
    'mode': mode,
    'maxTtlSeconds': maxTtlSeconds,
    'fixedTtlSeconds': fixedTtlSeconds,
    'minTtlEnabled': minTtlEnabled,
    'minTtlSeconds': minTtlSeconds,
    'staleFallbackEnabled': staleFallbackEnabled,
    'staleFallbackSeconds': staleFallbackSeconds,
    'negativeTtlEnabled': negativeTtlEnabled,
    'negativeTtlSeconds': negativeTtlSeconds,
    'optimistic': optimistic,
    'prefetchEnabled': prefetchEnabled,
    'prefetchThreshold': prefetchThreshold,
    'prefetchBeforeExpiryMs': prefetchBeforeExpiryMs,
    'excludePatterns': excludePatterns,
    'persistEnabled': persistEnabled,
    'persistPath': persistPath,
    'persistIntervalSeconds': persistIntervalSeconds,
  };
}

enum DesktopCacheEntryFilter {
  all,
  fresh,
  stale,
  negative;

  bool matches(DesktopCacheEntry entry) => switch (this) {
    all => true,
    fresh => !entry.isNegative && !entry.isStale,
    stale => !entry.isNegative && entry.isStale,
    negative => entry.isNegative,
  };
}
