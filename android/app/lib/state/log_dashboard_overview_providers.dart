library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_android/data/dns_type_name.dart';
import 'package:diting_android/data/log_dashboard_models.dart';
import 'package:diting_android/data/log_dashboard_rows.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

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

  final LogDnsQuality quality;
  final LogRaceSummary race;
  final LogBootstrapSummary bootstrap;
  final LogOffModeStats offMode;
  final List<LogRecentRequest> recentRequests;
  final List<LogCacheHotspot> cacheHotspots;
  final List<LogRaceWinner> raceWinners;
  final List<LogBootstrapIp> bootstrapIps;
  final List<LogSubscriptionBlock> subscriptionBlocks;

  int get highlightedTotal => breakdown.blocked + breakdown.error;

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

final logDashboardProvider = FutureProvider<LogDashboardSnapshot>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final mode = ref.watch(logModeProvider);
  final withHttp = ref.watch(workModeProvider).hasTunnelFeatures;
  final off = mode == LegacyLogMode.off;
  final filteredMode = mode == LegacyLogMode.blockedAndErrors;
  final sinceMs = _dayStartMillis();
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const LogDashboardSnapshot.empty();
  final subscriptionDb = off
      ? null
      : await ref.watch(subscriptionDatabaseProvider.future);
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

  var httpStats = const HttpRequestDailyStats.empty();
  if (!off && withHttp) {
    try {
      final parsed = core.rows(
        'http.daily',
        await _raw(db, 'http.daily', {'since': sinceMs}),
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
    await _raw(db, 'race.ranking', {'since': sinceMs, 'limit': _topListLimit}),
  );

  final names = providerDisplayNames(ref.watch(legacySettingsProvider));

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
    await _raw(db, 'cache.entries', {'now': nowMs, 'limit': _recentCacheLimit}),
    nowMs: nowMs,
  );

  final recentDns = core.rows(
    'dns.record',
    await _raw(db, filteredMode ? 'dns.blockedErrors.recent' : 'dns.recent', {
      'limit': _recentLogLimit,
    }),
  );
  var recentHttp = const <Map<String, Object?>>[];
  if (withHttp) {
    try {
      recentHttp = core.rows(
        'http.row',
        await _raw(db, 'http.query.recent', {
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
      await _raw(db, 'subscription.hits', {'table': 'dns', 'since': sinceMs}),
    );
    if (withHttp) {
      try {
        httpTotal = _count(
          core.rows(
            'count',
            await _raw(db, 'subscription.total', {
              'table': 'http',
              'since': sinceMs,
            }),
          ),
        );
        httpHits = core.rows(
          'subscriptionHit',
          await _raw(db, 'subscription.hits', {
            'table': 'http',
            'since': sinceMs,
          }),
        );
      } on DatabaseException {
        httpTotal = 0;
        httpHits = const [];
      }
    }
    if (subscriptionDb != null) {
      subscriptions = core.rows(
        'subscription.row',
        await _raw(subscriptionDb, 'subscription.rows'),
      );
    }
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

final logOverviewBreakdownProvider = Provider<LogTrafficBreakdown?>(
  (ref) =>
      ref.watch(logDashboardProvider.select((async) => async.value?.breakdown)),
);

final logOverviewQualityProvider = Provider<LogDnsQuality?>(
  (ref) =>
      ref.watch(logDashboardProvider.select((async) => async.value?.quality)),
);

final logOverviewRaceProvider = Provider<LogRaceSummary?>(
  (ref) => ref.watch(logDashboardProvider.select((async) => async.value?.race)),
);

final logOverviewBootstrapProvider = Provider<LogBootstrapSummary?>(
  (ref) =>
      ref.watch(logDashboardProvider.select((async) => async.value?.bootstrap)),
);

final logOverviewOffModeProvider = Provider<LogOffModeStats?>(
  (ref) =>
      ref.watch(logDashboardProvider.select((async) => async.value?.offMode)),
);

final logOverviewRecentRequestsProvider = Provider<List<LogRecentRequest>>(
  (ref) => ref.watch(
    logDashboardProvider.select(
      (async) => async.value?.recentRequests ?? const [],
    ),
  ),
);

final logOverviewCacheHotspotsProvider = Provider<List<LogCacheHotspot>>(
  (ref) => ref.watch(
    logDashboardProvider.select(
      (async) => async.value?.cacheHotspots ?? const [],
    ),
  ),
);

final logOverviewRaceWinnersProvider = Provider<List<LogRaceWinner>>(
  (ref) => ref.watch(
    logDashboardProvider.select(
      (async) => async.value?.raceWinners ?? const [],
    ),
  ),
);

final logOverviewBootstrapIpsProvider = Provider<List<LogBootstrapIp>>(
  (ref) => ref.watch(
    logDashboardProvider.select(
      (async) => async.value?.bootstrapIps ?? const [],
    ),
  ),
);

final logOverviewSubscriptionBlocksProvider =
    Provider<List<LogSubscriptionBlock>>(
      (ref) => ref.watch(
        logDashboardProvider.select(
          (async) => async.value?.subscriptionBlocks ?? const [],
        ),
      ),
    );

final logOverviewReadyProvider = Provider<bool>(
  (ref) => ref.watch(logDashboardProvider.select((async) => async.hasValue)),
);

final logOverviewHighlightedTotalProvider = Provider<int>(
  (ref) => ref.watch(
    logDashboardProvider.select((async) => async.value?.highlightedTotal ?? 0),
  ),
);
