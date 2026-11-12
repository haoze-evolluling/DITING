/// Real aggregates for the overview cards; one snapshot, or separate providers show contradictory
/// totals.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
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

Future<List<Map<String, Object?>>> _raw(
  Database db,
  String name, [
  Map<String, Object?> params = const {},
]) {
  final plan = RustLogQueryCore.instance.plan(name, params);
  return db.rawQuery(plan.sql, plan.args);
}

int _count(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? 0 : (rows.first['n'] as num?)?.toInt() ?? 0;

LogRecentRequest _recentOfKernel(Map<String, Object?> row) {
  final timestamp = (row['timestamp'] as num?)?.toInt() ?? 0;
  if (row['source'] == 'dns') {
    return logRecentRequestOfDns(
      DnsLogRecord(
        timestamp: timestamp,
        domain: row['domain'] as String? ?? '',
        queryType: (row['queryType'] as num?)?.toInt() ?? 1,
        result: row['result'] as String? ?? 'PASSED',
        cached: row['cached'] as bool? ?? false,
        message: row['message'] as String?,
        packageName: row['packageName'] as String?,
      ),
    );
  }
  return logRecentRequestOfHttp(
    HttpRequestRecord(
      id: 0,
      timestamp: timestamp,
      packageName: row['packageName'] as String? ?? '',
      protocol: row['protocol'] as String? ?? '',
      outcome: row['outcome'] as String? ?? '',
      authority: row['authority'] as String?,
      matchedRule: row['matchedRule'] as String?,
    ),
  );
}

/// Overview data. Empty tables yield [LogDashboardSnapshot.empty], never demo values.
final logDashboardProvider = FutureProvider<LogDashboardSnapshot>((ref) async {
  // Refresh and "clear logs" both bump this, or the overview goes stale.
  ref.watch(dnsLogRevisionProvider);
  final mode = ref.watch(logModeProvider);
  final normal = ref.watch(workModeProvider) == AppWorkMode.normal;
  final off = mode == LegacyLogMode.off;
  final filteredMode = mode == LegacyLogMode.blockedAndErrors;
  final sinceMs = _dayStartMillis();
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const LogDashboardSnapshot.empty();
  final core = RustLogQueryCore.instance;

  DnsLogDailyStats? dnsDaily;
  if (!off) {
    final parsed = core.rows(
      'dns.daily',
      await _raw(db, 'dns.daily', {'since': sinceMs}),
    );
    dnsDaily = parsed.isEmpty
        ? const DnsLogDailyStats.empty()
        : DnsLogDailyStats.fromParsed(parsed.first);
  }

  // Express/server, off mode, a missing database and an older schema all mean no HTTPS rows.
  var httpStats = const HttpRequestDailyStats.empty();
  final mainDb = await ref.watch(mainLogDatabaseProvider.future);
  if (!off && normal && mainDb != null) {
    try {
      final parsed = core.rows(
        'http.daily',
        await _raw(mainDb, 'http.daily', {'since': sinceMs}),
      );
      if (parsed.isNotEmpty) {
        httpStats = HttpRequestDailyStats.fromParsed(parsed.first);
      }
    } on DatabaseException {
      httpStats = const HttpRequestDailyStats.empty();
    }
  }

  final raceSummaryRows = core.rows(
    'race.summary',
    await _raw(db, 'race.summary', {'since': sinceMs}),
  );
  final raceSummary = raceSummaryRows.isEmpty
      ? const <String, Object?>{}
      : raceSummaryRows.first;
  final raceRanking = core.rows(
    'race.ranking',
    await _raw(db, 'race.ranking', {
      'since': sinceMs,
      'limit': _topListLimit,
    }),
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

  final bootstrapRows = core.rows(
    'bootstrap.stat',
    await _raw(db, 'bootstrap.recent', {'since': sinceMs}),
  );
  final cacheEntries = _count(
    core.rows('count', await _raw(db, 'cache.count', {'now': nowMs})),
  );
  final cacheHits = _count(core.rows('count', await _raw(db, 'cache.hits')));
  final cacheRows = core.rows(
    'cache.entry',
    await _raw(db, 'cache.entries', {
      'now': nowMs,
      'limit': _recentCacheLimit,
    }),
    nowMs: nowMs,
  );

  // Blocked-and-errors mode filters in SQL (legacy `recentLogs(limit, mode)`).
  final recentDns = core.rows(
    'dns.record',
    await _raw(db, filteredMode ? 'dns.blockedErrors.recent' : 'dns.recent', {
      'limit': _recentLogLimit,
    }),
  );
  var recentHttp = const <Map<String, Object?>>[];
  if (normal && mainDb != null) {
    try {
      recentHttp = core.rows(
        'http.row',
        await _raw(mainDb, 'http.query.recent', {
          'limit': _recentLogLimit,
          'status': 'all',
          'query': '',
        }),
      );
    } on DatabaseException {
      recentHttp = const [];
    }
  }

  var dnsTotal = 0;
  var httpTotal = 0;
  var dnsHits = const <Map<String, Object?>>[];
  var httpHits = const <Map<String, Object?>>[];
  var subscriptions = const <Map<String, Object?>>[];
  if (!off) {
    dnsTotal = _count(
      core.rows(
        'count',
        await _raw(db, 'subscription.total', {
          'table': 'dns',
          'since': sinceMs,
        }),
      ),
    );
    dnsHits = core.rows(
      'subscriptionHit',
      await _raw(db, 'subscription.hits', {
        'table': 'dns',
        'since': sinceMs,
      }),
    );
    if (normal && mainDb != null) {
      try {
        httpTotal = _count(
          core.rows(
            'count',
            await _raw(mainDb, 'subscription.total', {
              'table': 'http',
              'since': sinceMs,
            }),
          ),
        );
        httpHits = core.rows(
          'subscriptionHit',
          await _raw(mainDb, 'subscription.hits', {
            'table': 'http',
            'since': sinceMs,
          }),
        );
      } on DatabaseException {
        httpTotal = 0;
        httpHits = const [];
      }
    }
    subscriptions = core.rows(
      'subscription.row',
      await _raw(db, 'subscription.rows'),
    );
  }

  final answer = await deriveOffThread('overview', {
    'filteredMode': filteredMode,
    'off': off,
    'dnsDaily': dnsDaily?.toKernel(),
    'httpDaily': httpStats.toKernel(),
    'race': raceSummary,
    'raceRanking': raceRanking,
    'names': names,
    'bootstrapRows': bootstrapRows,
    'cacheEntries': cacheEntries,
    'cacheHits': cacheHits,
    'cacheRows': cacheRows,
    'recentDns': recentDns,
    'recentHttp': recentHttp,
    'dnsTotal': dnsTotal,
    'httpTotal': httpTotal,
    'dnsHits': dnsHits,
    'httpHits': httpHits,
    'subscriptions': subscriptions,
    'recentLimit': _recentLogLimit,
    'recentCacheLimit': _recentCacheLimit,
    'topLimit': _topListLimit,
    'subscriptionLimit': _subscriptionListLimit,
  });

  final breakdown = (answer['breakdown'] as Map?) ?? const {};
  int read(Object? map, String key) =>
      ((map as Map?)?[key] as num?)?.toInt() ?? 0;
  final quality = (answer['quality'] as Map?) ?? const {};
  final race = (answer['race'] as Map?) ?? const {};
  final bootstrap = (answer['bootstrap'] as Map?) ?? const {};
  final offMode = (answer['offMode'] as Map?) ?? const {};

  return LogDashboardSnapshot(
    breakdown: LogTrafficBreakdown(
      total: read(breakdown, 'total'),
      passed: read(breakdown, 'passed'),
      blocked: read(breakdown, 'blocked'),
      error: read(breakdown, 'error'),
      bypassed: read(breakdown, 'bypassed'),
      cached: read(breakdown, 'cached'),
    ),
    quality: LogDnsQuality(
      averageLatencyMs: (quality['averageLatencyMs'] as num?)?.toDouble(),
      latencySamples: (quality['latencySamples'] as num?)?.toInt() ?? 0,
      cacheHitRate: (quality['cacheHitRate'] as num?)?.toDouble() ?? 0,
    ),
    race: LogRaceSummary(
      requests: read(race, 'requests'),
      successes: read(race, 'successes'),
      averageElapsedMs: (race['averageElapsedMs'] as num?)?.toDouble() ?? 0,
    ),
    bootstrap: LogBootstrapSummary(
      attempts: read(bootstrap, 'attempts'),
      successes: read(bootstrap, 'successes'),
      averageElapsedMs:
          (bootstrap['averageElapsedMs'] as num?)?.toDouble() ?? 0,
    ),
    offMode: LogOffModeStats(
      cacheEntries: read(offMode, 'cacheEntries'),
      cacheHits: read(offMode, 'cacheHits'),
      raceRequests: read(offMode, 'raceRequests'),
      bootstrapAttempts: read(offMode, 'bootstrapAttempts'),
    ),
    recentRequests: [
      for (final row in answer['recent'] as List? ?? const [])
        _recentOfKernel((row as Map).cast<String, Object?>()),
    ],
    cacheHotspots: [
      for (final row in answer['cacheHotspots'] as List? ?? const [])
        LogCacheHotspot(
          queryName: (row as Map)['queryName'] as String? ?? '',
          queryType: dnsTypeName((row['queryType'] as num?)?.toInt() ?? 1),
          remainingSeconds: (row['remainingSeconds'] as num?)?.toInt() ?? 0,
          responseSize: (row['responseSize'] as num?)?.toInt() ?? 0,
          hitCount: (row['hitCount'] as num?)?.toInt() ?? 0,
        ),
    ],
    raceWinners: [
      for (final row in answer['raceWinners'] as List? ?? const [])
        LogRaceWinner(
          name: (row as Map)['name'] as String? ?? '',
          wins: (row['wins'] as num?)?.toInt() ?? 0,
          averageElapsedMs: (row['averageElapsedMs'] as num?)?.toDouble() ?? 0,
        ),
    ],
    bootstrapIps: [
      for (final row in answer['bootstrapIps'] as List? ?? const [])
        LogBootstrapIp(
          name: (row as Map)['name'] as String? ?? '',
          ip: row['ip'] as String? ?? '',
          attempts: (row['attempts'] as num?)?.toInt() ?? 0,
          successes: (row['successes'] as num?)?.toInt() ?? 0,
          averageElapsedMs: (row['averageElapsedMs'] as num?)?.toDouble() ?? 0,
        ),
    ],
    subscriptionBlocks: [
      for (final row in answer['subscriptionBlocks'] as List? ?? const [])
        LogSubscriptionBlock(
          name:
              (row as Map)['name'] as String? ??
              currentL10n.subscriptionDeletedWithId(
                (row['id'] as num?)?.toInt() ?? 0,
              ),
          enabled: row['enabled'] as bool? ?? false,
          deleted: row['deleted'] as bool? ?? false,
          hits: (row['hits'] as num?)?.toInt() ?? 0,
          rate: (row['rate'] as num?)?.toDouble() ?? 0,
        ),
    ],
  );
});

/// Per-card slices of the overview snapshot.
///
/// The snapshot is one object so no two cards can disagree, but reading it whole meant every card
/// rebuilt on the 10 s refresh even when only one slice had changed — the measured cost was an
/// 11–13 ms build spike for a screen where nothing visible moved. Each slice is compared with the
/// model's own `==`, so a card rebuilds only when its own figures differ.
final logOverviewBreakdownProvider = Provider<LogTrafficBreakdown?>(
  (ref) => ref.watch(logDashboardProvider.select((async) => async.value?.breakdown)),
);

final logOverviewQualityProvider = Provider<LogDnsQuality?>(
  (ref) => ref.watch(logDashboardProvider.select((async) => async.value?.quality)),
);

final logOverviewRaceProvider = Provider<LogRaceSummary?>(
  (ref) => ref.watch(logDashboardProvider.select((async) => async.value?.race)),
);

final logOverviewBootstrapProvider = Provider<LogBootstrapSummary?>(
  (ref) => ref.watch(logDashboardProvider.select((async) => async.value?.bootstrap)),
);

final logOverviewOffModeProvider = Provider<LogOffModeStats?>(
  (ref) => ref.watch(logDashboardProvider.select((async) => async.value?.offMode)),
);

final logOverviewRecentRequestsProvider = Provider<List<LogRecentRequest>>(
  (ref) => ref.watch(
    logDashboardProvider.select((async) => async.value?.recentRequests ?? const []),
  ),
);

final logOverviewCacheHotspotsProvider = Provider<List<LogCacheHotspot>>(
  (ref) => ref.watch(
    logDashboardProvider.select((async) => async.value?.cacheHotspots ?? const []),
  ),
);

final logOverviewRaceWinnersProvider = Provider<List<LogRaceWinner>>(
  (ref) => ref.watch(
    logDashboardProvider.select((async) => async.value?.raceWinners ?? const []),
  ),
);

final logOverviewBootstrapIpsProvider = Provider<List<LogBootstrapIp>>(
  (ref) => ref.watch(
    logDashboardProvider.select((async) => async.value?.bootstrapIps ?? const []),
  ),
);

final logOverviewSubscriptionBlocksProvider = Provider<List<LogSubscriptionBlock>>(
  (ref) => ref.watch(
    logDashboardProvider.select((async) => async.value?.subscriptionBlocks ?? const []),
  ),
);

/// `null` until the first read lands, which is what the cards use to show a dash instead of `0`.
final logOverviewReadyProvider = Provider<bool>(
  (ref) => ref.watch(logDashboardProvider.select((async) => async.hasValue)),
);

/// Highlighted total (blocked + failed), shared by the traffic-structure card.
final logOverviewHighlightedTotalProvider = Provider<int>(
  (ref) => ref.watch(
    logDashboardProvider.select((async) => async.value?.highlightedTotal ?? 0),
  ),
);
