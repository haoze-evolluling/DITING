/// Payloads for the resolver cache endpoints (`/api/v1/cache/*`).
///
/// Split from `desktop_api_fakes.dart` to keep each support file under the project's line limit;
/// `FakeDesktopBackend` imports these builders and serves them from its own mutable state.
library;

/// A `GET /api/v1/cache/stats` payload.
Map<String, Object?> cacheStatsPayload({
  bool enabled = true,
  int hits = 8000,
  int misses = 4000,
  int staleHits = 12,
  int negativeHits = 34,
  double hitRatio = 0.6667,
  int entryCount = 640,
  int maxEntries = 4096,
  int evictions = 12,
  int prefetchCount = 56,
}) => {
  'enabled': enabled,
  'totalHits': hits,
  'totalMisses': misses,
  'staleHits': staleHits,
  'negativeHits': negativeHits,
  'hitRatio': hitRatio,
  'entryCount': entryCount,
  'maxEntries': maxEntries,
  'evictionCount': evictions,
  'prefetchCount': prefetchCount,
};

/// A `GET /api/v1/cache/config` payload, with the service's own defaults.
Map<String, Object?> cacheConfigPayload({
  bool enabled = true,
  int maxEntries = 4096,
  String mode = 'limit_max_ttl',
  int maxTtlSeconds = 3600,
  int fixedTtlSeconds = 3600,
  bool minTtlEnabled = true,
  int minTtlSeconds = 60,
  bool staleFallbackEnabled = true,
  int staleFallbackSeconds = 300,
  bool negativeTtlEnabled = true,
  int negativeTtlSeconds = 30,
  bool optimistic = true,
  bool prefetchEnabled = false,
  int prefetchThreshold = 5,
  int prefetchBeforeExpiryMs = 30000,
  List<String> excludePatterns = const [],
  bool persistEnabled = false,
  String persistPath = '',
  int persistIntervalSeconds = 300,
}) => {
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

/// A `GET /api/v1/cache/entries` payload: one fresh name, one stale name and one negative one, so
/// the state chips have something to narrow.
Map<String, Object?> cacheEntriesPayload({
  int? total,
  List<Map<String, Object?>>? entries,
}) {
  final rows =
      entries ??
      const [
        {
          'domain': 'example.com.',
          'qtype': 'A',
          'ttl': 300,
          'originalTtl': 300,
          'remainingTtl': 210,
          'hitCount': 42,
          'isNegative': false,
          'status': 'fresh',
          'ipList': ['93.184.216.34'],
        },
        {
          'domain': 'cdn.example.net.',
          'qtype': 'AAAA',
          'ttl': 60,
          'originalTtl': 60,
          'remainingTtl': -5,
          'hitCount': 7,
          'isNegative': false,
          'status': 'stale',
          'ipList': ['2606:2800:220:1::1'],
        },
        {
          'domain': 'missing.example.org.',
          'qtype': 'A',
          'ttl': 30,
          'originalTtl': 30,
          'remainingTtl': 12,
          'hitCount': 3,
          'isNegative': true,
          'status': 'fresh',
        },
      ];
  return {'total': total ?? rows.length, 'entries': rows};
}

/// A `GET /api/v1/cache/top` payload.
List<Map<String, Object?>> cacheTopPayload() => const [
  {
    'domain': 'example.com.',
    'qtype': 'A',
    'hitCount': 42,
    'lastHitAt': 1700000000000,
  },
  {
    'domain': 'cdn.example.net.',
    'qtype': 'AAAA',
    'hitCount': 7,
    'lastHitAt': 1700000001000,
  },
];

/// A `GET /api/v1/cache/persist` (and dump/load) payload.
Map<String, Object?> cachePersistPayload({
  String path = r'C:\ProgramData\DITING\cache.json',
  int restored = 0,
  int entryCount = 640,
  bool persistOn = false,
  int intervalSec = 300,
  String lastError = '',
  int excludeHits = 9,
}) => {
  'path': path,
  if (restored > 0) 'restored': restored,
  'entryCount': entryCount,
  'persistOn': persistOn,
  'intervalSec': intervalSec,
  if (lastError.isNotEmpty) 'lastError': lastError,
  'excludeHits': excludeHits,
};
