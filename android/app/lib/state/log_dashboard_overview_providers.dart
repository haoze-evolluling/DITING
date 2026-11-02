/// Real aggregates for the overview cards; one snapshot, or separate providers show contradictory
/// totals.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/bootstrap_log_repository.dart';
import 'package:diting_android/data/db/dns_cache_repository.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/dns_type_name.dart';
import 'package:diting_android/data/log_dashboard_models.dart';
import 'package:diting_android/data/log_dashboard_rows.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// Legacy `RECENT_LOG_LIMIT`, `RECENT_CACHE_LIMIT`, `TOP_LIST_LIMIT`, `SUBSCRIPTION_LIST_LIMIT`.
const _recentLogLimit = 5;
const _recentCacheLimit = 5;
const _topListLimit = 8;
const _subscriptionListLimit = 5;

class LogDashboardSnapshot {
  const LogDashboardSnapshot({
    required this.breakdown,
    required this.quality,
    required this.race,
    required this.bootstrap,
    required this.offMode,
    required this.recentRequests,
    required this.cacheHotspots,
    required this.raceWinners,
    required this.bootstrapIps,
    required this.subscriptionBlocks,
  });

  /// Empty snapshot for a fresh install: genuine "no requests today" values, not placeholders.
  const LogDashboardSnapshot.empty()
    : breakdown = const LogTrafficBreakdown.empty(),
      quality = const LogDnsQuality.empty(),
      race = const LogRaceSummary.empty(),
      bootstrap = const LogBootstrapSummary.empty(),
      offMode = const LogOffModeStats.empty(),
      recentRequests = const [],
      cacheHotspots = const [],
      raceWinners = const [],
      bootstrapIps = const [],
      subscriptionBlocks = const [];

  final LogTrafficBreakdown breakdown;

  /// DNS quality (average latency, cache hit rate) from the same `dns_log` rows.
  final LogDnsQuality quality;
  final LogRaceSummary race;
  final LogBootstrapSummary bootstrap;
  final LogOffModeStats offMode;
  final List<LogRecentRequest> recentRequests;
  final List<LogCacheHotspot> cacheHotspots;
  final List<LogRaceWinner> raceWinners;
  final List<LogBootstrapIp> bootstrapIps;
  final List<LogSubscriptionBlock> subscriptionBlocks;

  /// Highlighted total: blocked plus failed (legacy `FilteredModeDashboard`).
  int get highlightedTotal => breakdown.blocked + breakdown.error;

  // The overview re-queries every 10 s; equal snapshots let the cards skip the rebuild.
  @override
  bool operator ==(Object other) =>
      other is LogDashboardSnapshot &&
      other.breakdown == breakdown &&
      other.quality == quality &&
      other.race == race &&
      other.bootstrap == bootstrap &&
      other.offMode == offMode &&
      listEquals(other.recentRequests, recentRequests) &&
      listEquals(other.cacheHotspots, cacheHotspots) &&
      listEquals(other.raceWinners, raceWinners) &&
      listEquals(other.bootstrapIps, bootstrapIps) &&
      listEquals(other.subscriptionBlocks, subscriptionBlocks);

  @override
  int get hashCode => Object.hash(
    breakdown,
    quality,
    race,
    bootstrap,
    offMode,
    Object.hashAll(recentRequests),
    Object.hashAll(cacheHotspots),
    Object.hashAll(raceWinners),
    Object.hashAll(bootstrapIps),
    Object.hashAll(subscriptionBlocks),
  );
}

/// Milliseconds at local midnight, matching the legacy `dayStartMillis()`.
int _dayStartMillis() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
}

/// Overview data. Empty tables yield [LogDashboardSnapshot.empty], never demo values.
final logDashboardProvider = FutureProvider<LogDashboardSnapshot>((ref) async {
  // Refresh and "clear logs" both bump this, or the overview goes stale.
  ref.watch(dnsLogRevisionProvider);
  final mode = ref.watch(logModeProvider);
  final express = ref.watch(workModeProvider) == AppWorkMode.express;
  final off = mode == LegacyLogMode.off;
  final filteredMode = mode == LegacyLogMode.blockedAndErrors;
  final since = DateTime.fromMillisecondsSinceEpoch(_dayStartMillis());

  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const LogDashboardSnapshot.empty();

  final dnsDaily = off
      ? null
      : await DnsLogRepository(db).dailyStats(since: since);

  // Express, off mode, a missing database and an older schema all mean no HTTPS rows.
  var httpStats = const HttpRequestDailyStats.empty();
  if (!off && !express) {
    final mainDb = await ref.watch(mainLogDatabaseProvider.future);
    if (mainDb != null) {
      try {
        httpStats = await HttpRequestRepository(mainDb)
            .dailyStats(since: since);
      } on DatabaseException {
        httpStats = const HttpRequestDailyStats.empty();
      }
    }
  }

  var httpPassed = 0;
  var httpBlocked = 0;
  var httpError = 0;
  var httpBypassed = 0;
  for (final entry in httpStats.byOutcome.entries) {
    if (filteredMode && httpOutcomeIsPassed(entry.key)) continue;
    switch (httpRowStatusOf(entry.key)) {
      case LogRowStatus.passed:
        httpPassed += entry.value;
      case LogRowStatus.filtered:
        httpBlocked += entry.value;
      case LogRowStatus.bypassed:
        httpBypassed += entry.value;
      case LogRowStatus.failed:
      case LogRowStatus.cached:
        httpError += entry.value;
    }
  }

  // Blocked-and-errors zeroes DNS passed/cached (legacy `copy(passed = 0, cached = 0)`), or the
  // ring lies.
  final dnsPassed = filteredMode ? 0 : (dnsDaily?.passed ?? 0);
  final dnsCached = filteredMode ? 0 : (dnsDaily?.cached ?? 0);
  final passed = dnsPassed + httpPassed;
  final blocked = (dnsDaily?.blocked ?? 0) + httpBlocked;
  final error = (dnsDaily?.error ?? 0) + httpError;

  final race = await _loadRace(ref, db, since);
  final bootstrap = await _loadBootstrap(db, since);
  final cache = DnsCacheRepository(db);
  final offMode = LogOffModeStats(
    cacheEntries: await cache.countUnexpired(),
    cacheHits: await cache.totalHitCount(),
    raceRequests: race.summary.requests,
    bootstrapAttempts: bootstrap.summary.attempts,
  );

  return LogDashboardSnapshot(
    breakdown: LogTrafficBreakdown(
      total: passed + blocked + error + httpBypassed,
      passed: passed,
      blocked: blocked,
      error: error,
      bypassed: httpBypassed,
      cached: dnsCached,
    ),
    // Latency is null without samples; filtered mode recomputes the hit rate, cached hits would
    // lie.
    quality: dnsDaily == null
        ? const LogDnsQuality.empty()
        : LogDnsQuality(
            averageLatencyMs: dnsDaily.latencySamples == 0
                ? null
                : dnsDaily.averageLatencyMs.toDouble(),
            latencySamples: dnsDaily.latencySamples,
            cacheHitRate: filteredMode ? 0 : dnsDaily.cacheHitRate,
          ),
    race: race.summary,
    bootstrap: bootstrap.summary,
    offMode: offMode,
    recentRequests: off
        ? const []
        : await _loadRecentRequests(
            ref,
            db,
            express: express,
            filtered: filteredMode,
          ),
    cacheHotspots: await _loadCacheHotspots(cache),
    raceWinners: race.winners,
    bootstrapIps: bootstrap.ips,
    subscriptionBlocks: off
        ? const []
        : await _loadSubscriptionBlocks(db, since, express: express),
  );
});

class _RaceSlice {
  const _RaceSlice({required this.summary, required this.winners});

  final LogRaceSummary summary;
  final List<LogRaceWinner> winners;
}

Future<_RaceSlice> _loadRace(Ref ref, Database db, DateTime since) async {
  final start = since.millisecondsSinceEpoch;
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS requests, '
    'COALESCE(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END), 0) AS successes, '
    'AVG(elapsedMs) AS avgElapsed FROM dns_race_log WHERE timestamp >= ?',
    [start],
  );
  final row = rows.isEmpty ? null : rows.first;
  final summary = LogRaceSummary(
    requests: (row?['requests'] as num?)?.toInt() ?? 0,
    successes: (row?['successes'] as num?)?.toInt() ?? 0,
    averageElapsedMs: ((row?['avgElapsed'] as num?) ?? 0).toDouble(),
  );

  final ranking = await db.rawQuery(
    'SELECT winnerProviderId AS providerId, COUNT(*) AS wins, '
    'AVG(CASE WHEN winnerElapsedMs IS NOT NULL THEN winnerElapsedMs END) '
    'AS avgElapsed FROM dns_race_log '
    'WHERE success = 1 AND winnerProviderId IS NOT NULL AND timestamp >= ? '
    'GROUP BY winnerProviderId ORDER BY wins DESC, avgElapsed ASC LIMIT ?',
    [start, _topListLimit],
  );

  // Share the catalog with the race page, or one provider appears under two names.
  final settings = ref.watch(legacySettingsProvider);
  final names = {
    for (final provider in [
      ...defaultDnsProviders(currentL10n),
      ...parseUserProviders(settings.userProvidersJson),
    ])
      provider.id: provider.name,
  };

  return _RaceSlice(
    summary: summary,
    winners: [
      for (final entry in ranking)
        if ((entry['providerId'] as String?)?.isNotEmpty == true)
          LogRaceWinner(
            name: names[entry['providerId']] ?? entry['providerId']! as String,
            wins: (entry['wins'] as num?)?.toInt() ?? 0,
            averageElapsedMs: ((entry['avgElapsed'] as num?) ?? 0).toDouble(),
          ),
    ],
  );
}

class _BootstrapSlice {
  const _BootstrapSlice({required this.summary, required this.ips});

  final LogBootstrapSummary summary;
  final List<LogBootstrapIp> ips;
}

Future<_BootstrapSlice> _loadBootstrap(Database db, DateTime since) async {
  // `recentStats` takes a window length, so "today" is time since local midnight.
  final window = DateTime.now().difference(since);
  final stats = await BootstrapLogRepository(db)
      .recentStats(window: window < Duration.zero ? Duration.zero : window);

  var attempts = 0;
  var successes = 0;
  var weighted = 0.0;
  for (final stat in stats) {
    attempts += stat.attempts;
    successes += stat.successes;
    weighted += (stat.averageElapsedMs ?? 0) * stat.attempts;
  }
  return _BootstrapSlice(
    summary: LogBootstrapSummary(
      attempts: attempts,
      successes: successes,
      averageElapsedMs: attempts == 0 ? 0 : weighted / attempts,
    ),
    ips: [
      for (final stat in stats.take(_topListLimit))
        LogBootstrapIp(
          name: stat.name,
          ip: stat.ip,
          attempts: stat.attempts,
          successes: stat.successes,
          averageElapsedMs: stat.averageElapsedMs ?? 0,
        ),
    ],
  );
}

Future<List<LogRecentRequest>> _loadRecentRequests(
  Ref ref,
  Database db, {
  required bool express,
  required bool filtered,
}) async {
  // Blocked-and-errors mode filters in SQL (legacy `recentLogs(limit, mode)`).
  final dnsRows = await db.query(
    'dns_log',
    where: filtered ? "result IN ('BLOCKED', 'ERROR')" : null,
    orderBy: 'timestamp DESC, id DESC',
    limit: _recentLogLimit,
  );
  final dnsLogs = [
    for (final row in dnsRows)
      DnsLogRecord(
        timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
        domain: row['queryName'] as String? ?? '',
        queryType: (row['queryType'] as num?)?.toInt() ?? 0,
        result: row['result'] as String? ?? 'PASSED',
        cached: (row['cached'] as num?)?.toInt() == 1,
        message: row['message'] as String?,
        packageName: row['packageName'] as String?,
      ),
  ];

  var httpRows = const <HttpRequestRecord>[];
  if (!express) {
    final mainDb = await ref.watch(mainLogDatabaseProvider.future);
    if (mainDb != null) {
      try {
        httpRows = await HttpRequestRepository(mainDb)
            .recent(limit: _recentLogLimit);
      } on DatabaseException {
        httpRows = const [];
      }
    }
  }

  final merged = <({int timestamp, LogRecentRequest row})>[
    for (final row in dnsLogs)
      (timestamp: row.timestamp, row: logRecentRequestOfDns(row)),
    for (final row in httpRows)
      if (!filtered || !httpOutcomeIsPassed(row.outcome))
        (timestamp: row.timestamp, row: logRecentRequestOfHttp(row)),
  ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return [for (final entry in merged.take(_recentLogLimit)) entry.row];
}

Future<List<LogCacheHotspot>> _loadCacheHotspots(
  DnsCacheRepository repository,
) async {
  final entries = await repository.entries(limit: _recentCacheLimit);
  return [
    for (final entry in entries)
      LogCacheHotspot(
        queryName: entry.domain,
        queryType: dnsTypeName(entry.queryType),
        remainingSeconds: entry.remainingTtlSeconds,
        responseSize: entry.responseSize,
        hitCount: entry.hitCount,
      ),
  ];
}

Future<List<LogSubscriptionBlock>> _loadSubscriptionBlocks(
  Database db,
  DateTime since, {
  required bool express,
}) async {
  final start = since.millisecondsSinceEpoch;
  final hits = <int, int>{};
  var total = 0;

  final dnsTotal = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM dns_log WHERE timestamp >= ?',
    [start],
  );
  total += (dnsTotal.first['n'] as num?)?.toInt() ?? 0;

  final dnsHits = await db.rawQuery(
    'SELECT blockSubscriptionId AS id, COUNT(*) AS hits FROM dns_log '
    "WHERE result = 'BLOCKED' AND blockSubscriptionId IS NOT NULL "
    'AND timestamp >= ? GROUP BY blockSubscriptionId',
    [start],
  );
  for (final row in dnsHits) {
    final id = (row['id'] as num?)?.toInt();
    if (id == null) continue;
    hits[id] = (hits[id] ?? 0) + ((row['hits'] as num?)?.toInt() ?? 0);
  }

  if (!express) {
    // No `http_request_log` (express) or no column (old schema): no HTTPS hits.
    try {
      final httpTotal = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM http_request_log WHERE timestamp >= ?',
        [start],
      );
      total += (httpTotal.first['n'] as num?)?.toInt() ?? 0;

      final httpHits = await db.rawQuery(
        'SELECT blockSubscriptionId AS id, COUNT(*) AS hits '
        'FROM http_request_log '
        "WHERE outcome IN ('blocked', 'invalid') "
        'AND blockSubscriptionId IS NOT NULL AND timestamp >= ? '
        'GROUP BY blockSubscriptionId',
        [start],
      );
      for (final row in httpHits) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        hits[id] = (hits[id] ?? 0) + ((row['hits'] as num?)?.toInt() ?? 0);
      }
    } on DatabaseException {
      // Missing table or column: no HTTPS rows to count.
    }
  }

  if (total == 0 && hits.isEmpty) return const [];

  final subscriptions = await db.query(
    'subscription',
    columns: ['id', 'name', 'enabled'],
  );
  final byId = {
    for (final row in subscriptions)
      (row['id'] as num?)?.toInt() ?? 0: (
        name: row['name'] as String? ?? '',
        enabled: (row['enabled'] as num?)?.toInt() == 1,
      ),
  };

  final blocks = [
    for (final entry in hits.entries)
      LogSubscriptionBlock(
        name:
            byId[entry.key]?.name ??
            currentL10n.subscriptionDeletedWithId(entry.key),
        enabled: byId[entry.key]?.enabled ?? false,
        deleted: !byId.containsKey(entry.key),
        hits: entry.value,
        rate: total == 0 ? 0 : entry.value / total,
      ),
  ]..sort((a, b) => b.hits.compareTo(a.hits));
  return blocks.take(_subscriptionListLimit).toList();
}
