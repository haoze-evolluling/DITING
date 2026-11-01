/// Immutable models of what the desktop pages read from the local service.
///
/// Only the fields a card shows are parsed. Every parser tolerates a missing or mistyped value,
/// because the service answers with `omitempty` fields and an older build must not crash the UI.
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

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

/// `GET /api/v1/status`.
class DesktopStatus {
  const DesktopStatus({
    required this.version,
    required this.pid,
    required this.uptime,
    required this.dns,
    required this.takeover,
    required this.metrics,
    required this.cache,
    required this.filter,
  });

  factory DesktopStatus.fromJson(Map<String, Object?> json) {
    final dns = _map(json['dns']);
    final metrics = _map(json['metrics']);
    return DesktopStatus(
      version: '${json['version'] ?? ''}',
      pid: _int(json['pid']),
      uptime: Duration(seconds: _int(json['uptimeSeconds'])),
      dns: DnsServiceState(
        running: _bool(dns['running']),
        listenAddresses: _strings(dns['listenAddresses']),
        allowLan: _bool(dns['allowLAN']),
        lanAddresses: _strings(dns['lanAddresses']),
        mode: '${dns['mode'] ?? ''}',
      ),
      takeover: TakeoverState(
        active: _bool(_map(json['takeover'])['active']),
        adapters: _strings([
          for (final adapter
              in _map(json['takeover'])['adapters'] as List? ?? [])
            _map(adapter)['id'],
        ]).where((id) => id.isNotEmpty).toList(),
      ),
      metrics: QueryMetrics(
        total: _int(metrics['totalQueries']),
        success: _int(metrics['successQueries']),
        failed: _int(metrics['failedQueries']),
        averageLatencyMs: _double(metrics['avgLatencyMs']),
        qps: _double(metrics['qps']),
      ),
      cache: CacheStats.fromJson(_map(json['cache'])),
      filter: FilterStats.fromJson(_map(json['filter'])),
    );
  }

  final String version;
  final int pid;
  final Duration uptime;
  final DnsServiceState dns;
  final TakeoverState takeover;
  final QueryMetrics metrics;
  final CacheStats cache;
  final FilterStats filter;
}

class DnsServiceState {
  const DnsServiceState({
    required this.running,
    required this.listenAddresses,
    required this.allowLan,
    required this.lanAddresses,
    required this.mode,
  });

  final bool running;
  final List<String> listenAddresses;
  final bool allowLan;
  final List<String> lanAddresses;
  final String mode;

  /// `127.0.0.1:5353`, or empty when the listener is down.
  String get listenSummary => listenAddresses.join(' · ');
}

class TakeoverState {
  const TakeoverState({required this.active, required this.adapters});

  final bool active;
  final List<String> adapters;
}

class QueryMetrics {
  const QueryMetrics({
    required this.total,
    required this.success,
    required this.failed,
    required this.averageLatencyMs,
    required this.qps,
  });

  final int total;
  final int success;
  final int failed;
  final double averageLatencyMs;
  final double qps;
}

/// `core.CacheStats`.
class CacheStats {
  const CacheStats({
    required this.enabled,
    required this.hits,
    required this.misses,
    required this.hitRatio,
    required this.entries,
    required this.maxEntries,
    required this.evictions,
  });

  factory CacheStats.fromJson(Map<String, Object?> json) => CacheStats(
    enabled: _bool(json['enabled']),
    hits: _int(json['totalHits']),
    misses: _int(json['totalMisses']),
    hitRatio: _double(json['hitRatio']),
    entries: _int(json['entryCount']),
    maxEntries: _int(json['maxEntries']),
    evictions: _int(json['evictionCount']),
  );

  final bool enabled;
  final int hits;
  final int misses;
  final double hitRatio;
  final int entries;
  final int maxEntries;
  final int evictions;
}

/// `core.FilterStats`.
class FilterStats {
  const FilterStats({
    required this.enabled,
    required this.rules,
    required this.activeLists,
    required this.totalQueries,
    required this.blocked,
    required this.blockRate,
    required this.paused,
    required this.pausedRemaining,
  });

  factory FilterStats.fromJson(Map<String, Object?> json) => FilterStats(
    enabled: _bool(json['enabled']),
    rules: _int(json['totalRules']),
    activeLists: _int(json['activeLists']),
    totalQueries: _int(json['totalQueries']),
    blocked: _int(json['blockedQueries']),
    blockRate: _double(json['blockRate']),
    paused: _bool(json['paused']),
    pausedRemaining: Duration(seconds: _int(json['pausedRemainingSec'])),
  );

  final bool enabled;
  final int rules;
  final int activeLists;
  final int totalQueries;
  final int blocked;
  final double blockRate;
  final bool paused;
  final Duration pausedRemaining;
}

/// `GET /api/v1/service/status` — the host service, not the DNS listener.
class CoreServiceState {
  const CoreServiceState({
    required this.installed,
    required this.running,
    required this.stateText,
    required this.autoStart,
  });

  factory CoreServiceState.fromJson(Map<String, Object?> json) =>
      CoreServiceState(
        installed: _bool(json['installed']),
        running: _bool(json['running']),
        stateText: '${json['stateText'] ?? ''}',
        autoStart: switch (_map(json['autoStart'])['enabled']) {
          final Object value? => _bool(value),
          _ => null,
        },
      );

  final bool installed;
  final bool running;
  final String stateText;

  /// Null when an older service does not report auto-start at all.
  final bool? autoStart;
}

/// One `querylog.Record` from `GET /api/v1/querylog/search`.
class QueryLogEntry {
  const QueryLogEntry({
    required this.timestamp,
    required this.domain,
    required this.qtype,
    required this.client,
    required this.durationMs,
    required this.status,
    required this.blocked,
    required this.cached,
  });

  factory QueryLogEntry.fromJson(Map<String, Object?> json) {
    final name = '${json['clientName'] ?? ''}';
    return QueryLogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        _int(json['ts']),
        isUtc: true,
      ).toLocal(),
      domain: '${json['domain'] ?? ''}',
      qtype: '${json['qtype'] ?? ''}',
      client: name.isNotEmpty ? name : '${json['clientIP'] ?? ''}',
      durationMs: _double(json['durationMs']),
      status: '${json['status'] ?? ''}',
      blocked: _bool(json['blocked']),
      cached: _bool(json['cached']),
    );
  }

  final DateTime timestamp;
  final String domain;
  final String qtype;
  final String client;
  final double durationMs;
  final String status;
  final bool blocked;
  final bool cached;

  /// The service stores the trailing dot of the queried name; it reads as noise in a table.
  String get displayDomain =>
      domain.endsWith('.') ? domain.substring(0, domain.length - 1) : domain;
}

/// `querylog.SearchResult`: the total count plus the page the limit asked for.
class QueryLogPage {
  const QueryLogPage({required this.total, required this.entries});

  factory QueryLogPage.fromJson(Map<String, Object?> json) => QueryLogPage(
    total: _int(json['total']),
    entries: [
      for (final entry in json['entries'] as List? ?? const [])
        if (entry is Map) QueryLogEntry.fromJson(entry.cast<String, Object?>()),
    ],
  );

  final int total;
  final List<QueryLogEntry> entries;
}

/// `GET /api/v1/querylog/stats` — the service's own 24-hour rolling window. The trend and top-N
/// lists of the same answer are not parsed: no desktop page shows them yet.
class DesktopQueryStats {
  const DesktopQueryStats({required this.summary});

  static const empty = DesktopQueryStats(summary: QueryStatsSummary.empty);

  factory DesktopQueryStats.fromJson(Map<String, Object?> json) =>
      DesktopQueryStats(
        summary: QueryStatsSummary.fromJson(_map(json['summary'])),
      );

  final QueryStatsSummary summary;
}

/// `querylog.Summary`.
class QueryStatsSummary {
  const QueryStatsSummary({
    required this.queries,
    required this.blocked,
    required this.cached,
    required this.forwarded,
    required this.errors,
    required this.averageResponseMs,
    required this.cacheHitRate,
  });

  static const empty = QueryStatsSummary(
    queries: 0,
    blocked: 0,
    cached: 0,
    forwarded: 0,
    errors: 0,
    averageResponseMs: 0,
    cacheHitRate: 0,
  );

  factory QueryStatsSummary.fromJson(Map<String, Object?> json) =>
      QueryStatsSummary(
        queries: _int(json['queries']),
        blocked: _int(json['blocked']),
        cached: _int(json['cached']),
        forwarded: _int(json['forwarded']),
        errors: _int(json['errors']),
        averageResponseMs: _double(json['avgResponseMs']),
        cacheHitRate: _double(json['cacheHitRate']),
      );

  final int queries;
  final int blocked;
  final int cached;
  final int forwarded;
  final int errors;
  final double averageResponseMs;

  /// 0..1.
  final double cacheHitRate;

  /// Everything the window saw that was not blocked, including cache hits.
  int get passed => (queries - blocked).clamp(0, queries);
}

/// The record types the console offers as one-tap filters, in the order the old desktop console
/// lists them (`frontend/src/components/overview/QueryHistoryPanel.vue`). Empty means no filter.
const List<String> desktopLogQTypes = ['A', 'AAAA', 'HTTPS', 'CNAME', 'PTR', 'TXT'];

/// The `status` values `querylog.SearchQuery` accepts; the empty one means "no filter".
///
/// The words the filter shows are the log page's own ARB keys, so this enum carries only the
/// value the service understands.
enum DesktopLogStatus {
  all(''),
  passed('allowed'),
  blocked('blocked'),
  cached('cached'),
  error('error');

  const DesktopLogStatus(this.apiValue);

  final String apiValue;
}
