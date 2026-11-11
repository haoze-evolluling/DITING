/// Data layer for the drill-down pages; overview cards and race queries live in their own files.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/bootstrap_log_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// Range for the race and bootstrap pages, matching legacy `RaceStatsRange` and
/// `BootstrapStatsRange`.
enum LogStatsRange {
  today,
  sevenDays,
  all;

  String label(AppL10n l10n) => switch (this) {
    LogStatsRange.today => l10n.commonToday,
    LogStatsRange.sevenDays => l10n.logWindowSevenDays,
    LogStatsRange.all => l10n.commonAll,
  };

  /// Window start; null means no lower bound.
  DateTime? startOf(DateTime now) {
    final dayStart = DateTime(now.year, now.month, now.day);
    return switch (this) {
      LogStatsRange.today => dayStart,
      LogStatsRange.sevenDays => dayStart.subtract(const Duration(days: 6)),
      LogStatsRange.all => null,
    };
  }
}

/// Range for the subscription interception page, with the legacy
/// `SubscriptionInterceptionStatsRange` labels.
enum SubscriptionStatsRange {
  today,
  sevenDays,
  all;

  String label(AppL10n l10n) => switch (this) {
    SubscriptionStatsRange.today => l10n.commonToday,
    SubscriptionStatsRange.sevenDays => l10n.logWindowSevenDaysRecent,
    SubscriptionStatsRange.all => l10n.commonAll,
  };

  DateTime? startOf(DateTime now) {
    final dayStart = DateTime(now.year, now.month, now.day);
    return switch (this) {
      SubscriptionStatsRange.today => dayStart,
      SubscriptionStatsRange.sevenDays => dayStart.subtract(
        const Duration(days: 6),
      ),
      SubscriptionStatsRange.all => null,
    };
  }
}

class BootstrapStatsRangeNotifier extends Notifier<LogStatsRange> {
  @override
  LogStatsRange build() => LogStatsRange.today;

  void select(LogStatsRange range) {
    if (state == range) return;
    state = range;
  }
}

final bootstrapStatsRangeProvider =
    NotifierProvider<BootstrapStatsRangeNotifier, LogStatsRange>(
      BootstrapStatsRangeNotifier.new,
    );

/// Selected subscription interception window.
class SubscriptionStatsRangeNotifier extends Notifier<SubscriptionStatsRange> {
  @override
  SubscriptionStatsRange build() => SubscriptionStatsRange.today;

  void select(SubscriptionStatsRange range) {
    if (state == range) return;
    state = range;
  }
}

final subscriptionStatsRangeProvider =
    NotifierProvider<SubscriptionStatsRangeNotifier, SubscriptionStatsRange>(
      SubscriptionStatsRangeNotifier.new,
    );

/// Supplementary `dns_cache.lastHitAt` query matching `DnsCacheRepository.entries`; null means
/// never hit.
final cacheLastHitProvider = FutureProvider<Map<String, int?>>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const {};
  final now = DateTime.now().millisecondsSinceEpoch;
  final plan = RustLogQueryCore.instance.plan('cache.lastHit', {
    'now': now,
    'limit': 200,
  });
  final rows = await db.rawQuery(plan.sql, plan.args);
  return {
    for (final row in RustLogQueryCore.instance.rows('cacheLastHit', rows))
      '${row['queryName'] as String? ?? ''}|'
              '${(row['queryType'] as num?)?.toInt() ?? 1}':
          (row['lastHitAt'] as num?)?.toInt(),
  };
});

class BootstrapStatsSnapshot {
  const BootstrapStatsSnapshot({
    required this.attempts,
    required this.successes,
    required this.failures,
    required this.averageElapsedMs,
    required this.ips,
  });

  const BootstrapStatsSnapshot.empty()
    : attempts = 0,
      successes = 0,
      failures = 0,
      averageElapsedMs = 0,
      ips = const [];

  final int attempts;
  final int successes;
  final int failures;

  /// Attempt-weighted average elapsed time; 0 when there are no samples.
  final double averageElapsedMs;
  final List<BootstrapIpStat> ips;

  double get successRate => attempts == 0 ? 0 : successes / attempts;
}

final bootstrapStatsProvider = FutureProvider<BootstrapStatsSnapshot>((
  ref,
) async {
  ref.watch(dnsLogRevisionProvider);
  final range = ref.watch(bootstrapStatsRangeProvider);
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const BootstrapStatsSnapshot.empty();

  // `recentStats` takes a window length, so "today" is time since midnight.
  final now = DateTime.now();
  final start = range.startOf(now);
  final window = start == null
      ? const Duration(days: 3650)
      : now.difference(start);
  final ips = await BootstrapLogRepository(db).recentStats(window: window);
  final summary = RustLogQueryCore.instance.derive('bootstrap.stats', {
    'rows': [for (final ip in ips) ip.toKernel()],
  });
  return BootstrapStatsSnapshot(
    attempts: (summary['attempts'] as num?)?.toInt() ?? 0,
    successes: (summary['successes'] as num?)?.toInt() ?? 0,
    failures: (summary['failures'] as num?)?.toInt() ?? 0,
    averageElapsedMs:
        (summary['averageElapsedMs'] as num?)?.toDouble() ?? 0,
    ips: ips,
  );
});

class SubscriptionInterceptionItem {
  const SubscriptionInterceptionItem({
    required this.id,
    required this.name,
    required this.enabled,
    required this.deleted,
    required this.hits,
    required this.rate,
  });

  final int id;
  final String name;
  final bool enabled;

  /// The subscription was deleted but its hits remain in the logs.
  final bool deleted;
  final int hits;

  /// Share of all recorded requests (0..1).
  final double rate;

  String get statusLabel {
    if (deleted) return currentL10n.subscriptionDeleted;
    return enabled ? currentL10n.commonEnabled : currentL10n.subscriptionDisabled;
  }
}

class SubscriptionInterceptionSnapshot {
  const SubscriptionInterceptionSnapshot({
    required this.totalRequests,
    required this.items,
    this.missingColumn = false,
  });

  const SubscriptionInterceptionSnapshot.empty()
    : totalRequests = 0,
      items = const [],
      missingColumn = false;

  /// All recorded DNS and HTTPS requests in the window (the rate denominator).
  final int totalRequests;
  final List<SubscriptionInterceptionItem> items;

  /// The legacy database lacks `blockSubscriptionId`, so no rate can be computed.
  final bool missingColumn;
}

/// Legacy SQL: the denominator is every row of both tables, the numerator only `result = BLOCKED`
/// rows.
final subscriptionInterceptionProvider =
    FutureProvider<SubscriptionInterceptionSnapshot>((ref) async {
      ref.watch(dnsLogRevisionProvider);
      final range = ref.watch(subscriptionStatsRangeProvider);
      final db = await ref.watch(activeLogDatabaseProvider.future);
      if (db == null) return const SubscriptionInterceptionSnapshot.empty();
      final since = range.startOf(DateTime.now())?.millisecondsSinceEpoch;
      final core = RustLogQueryCore.instance;

      Future<List<Map<String, Object?>>> raw(
        Database db,
        String name, [
        Map<String, Object?> params = const {},
      ]) {
        final plan = core.plan(name, params);
        return db.rawQuery(plan.sql, plan.args);
      }

      int count(List<Map<String, Object?>> rows) =>
          rows.isEmpty ? 0 : (rows.first['n'] as num?)?.toInt() ?? 0;

      try {
        var total = count(
          core.rows(
            'count',
            await raw(db, 'subscription.total', {
              'table': 'dns',
              if (since != null) 'since': since,
            }),
          ),
        );
        final hits = [
          ...core.rows(
            'subscriptionHit',
            await raw(db, 'subscription.hits', {
              'table': 'dns',
              if (since != null) 'since': since,
            }),
          ),
        ];

        // Express has no `http_request_log`: no HTTPS records, DNS side unaffected.
        var httpsAvailable = true;
        try {
          total += count(
            core.rows(
              'count',
              await raw(db, 'subscription.total', {
                'table': 'http',
                if (since != null) 'since': since,
              }),
            ),
          );
          hits.addAll(
            core.rows(
              'subscriptionHit',
              await raw(db, 'subscription.hits', {
                'table': 'http',
                if (since != null) 'since': since,
              }),
            ),
          );
        } on DatabaseException {
          httpsAvailable = false;
        }

        if (!httpsAvailable && total == 0) {
          return const SubscriptionInterceptionSnapshot.empty();
        }

        final subscriptions = core.rows(
          'subscription.row',
          await raw(db, 'subscription.rows'),
        );
        final answer = core.derive('subscription.stats', {
          'total': total,
          'hits': hits,
          'subscriptions': subscriptions,
          'sortByName': true,
        });
        final items = [
          for (final row in answer['items'] as List? ?? const [])
            () {
              final map = (row as Map).cast<String, Object?>();
              final deleted = map['deleted'] as bool? ?? false;
              final id = (map['id'] as num?)?.toInt() ?? 0;
              return SubscriptionInterceptionItem(
                id: id,
                name:
                    map['name'] as String? ??
                    currentL10n.subscriptionDeletedWithId(id),
                enabled: map['enabled'] as bool? ?? false,
                deleted: deleted,
                hits: (map['hits'] as num?)?.toInt() ?? 0,
                rate: (map['rate'] as num?)?.toDouble() ?? 0,
              );
            }(),
        ]..sort((a, b) {
          final byHits = b.hits.compareTo(a.hits);
          return byHits != 0 ? byHits : a.name.compareTo(b.name);
        });

        return SubscriptionInterceptionSnapshot(
          totalRequests: total,
          items: items,
        );
      } on DatabaseException catch (error) {
        // Older databases lack `subscriptionId` (added in 1.4.3); report the gap instead of an
        // all-zero table.
        if (error.toString().contains('no such column')) {
          return const SubscriptionInterceptionSnapshot(
            totalRequests: 0,
            items: [],
            missingColumn: true,
          );
        }
        rethrow;
      }
    });
