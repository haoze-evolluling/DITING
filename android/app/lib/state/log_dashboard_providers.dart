library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/db/bootstrap_log_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

enum LogStatsRange {
  today,
  sevenDays,
  all;

  String label(AppL10n l10n) => switch (this) {
    LogStatsRange.today => l10n.commonToday,
    LogStatsRange.sevenDays => l10n.logWindowSevenDays,
    LogStatsRange.all => l10n.commonAll,
  };

  DateTime? startOf(DateTime now) {
    final dayStart = DateTime(now.year, now.month, now.day);
    return switch (this) {
      LogStatsRange.today => dayStart,
      LogStatsRange.sevenDays => dayStart.subtract(const Duration(days: 6)),
      LogStatsRange.all => null,
    };
  }
}

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

final cacheLastHitProvider = FutureProvider<Map<String, int?>>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const {};
  final core = RustLogQueryCore.instance;
  final now = DateTime.now().millisecondsSinceEpoch;
  final plan = core.plan('cache.lastHit', {'now': now, 'limit': 200});
  final rows = await db.rawQuery(plan.sql, plan.args);
  return {
    for (final row in core.rows('cacheLastHit', rows))
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
    averageElapsedMs: (summary['averageElapsedMs'] as num?)?.toDouble() ?? 0,
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

  final bool deleted;
  final int hits;

  final double rate;

  String get statusLabel {
    if (deleted) return currentL10n.subscriptionDeleted;
    return enabled
        ? currentL10n.commonEnabled
        : currentL10n.subscriptionDisabled;
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

  final int totalRequests;
  final List<SubscriptionInterceptionItem> items;

  final bool missingColumn;
}

SubscriptionInterceptionItem _interceptionItemOf(Map<String, Object?> row) {
  final id = (row['id'] as num?)?.toInt() ?? 0;
  return SubscriptionInterceptionItem(
    id: id,
    name: row['name'] as String? ?? currentL10n.subscriptionDeletedWithId(id),
    enabled: row['enabled'] as bool? ?? false,
    deleted: row['deleted'] as bool? ?? false,
    hits: (row['hits'] as num?)?.toInt() ?? 0,
    rate: (row['rate'] as num?)?.toDouble() ?? 0,
  );
}

final subscriptionInterceptionProvider =
    FutureProvider<SubscriptionInterceptionSnapshot>((ref) async {
      ref.watch(dnsLogRevisionProvider);
      final range = ref.watch(subscriptionStatsRangeProvider);
      final db = await ref.watch(activeLogDatabaseProvider.future);
      if (db == null) return const SubscriptionInterceptionSnapshot.empty();
      final subscriptionDb = await ref.watch(
        subscriptionDatabaseProvider.future,
      );
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
              'since': ?since,
            }),
          ),
        );
        final hits = [
          ...core.rows(
            'subscriptionHit',
            await raw(db, 'subscription.hits', {
              'table': 'dns',
              'since': ?since,
            }),
          ),
        ];

        var httpsAvailable = true;
        try {
          total += count(
            core.rows(
              'count',
              await raw(db, 'subscription.total', {
                'table': 'http',
                'since': ?since,
              }),
            ),
          );
          hits.addAll(
            core.rows(
              'subscriptionHit',
              await raw(db, 'subscription.hits', {
                'table': 'http',
                'since': ?since,
              }),
            ),
          );
        } on DatabaseException {
          httpsAvailable = false;
        }

        if (!httpsAvailable && total == 0) {
          return const SubscriptionInterceptionSnapshot.empty();
        }

        final subscriptions = subscriptionDb == null
            ? const <Map<String, Object?>>[]
            : core.rows(
                'subscription.row',
                await raw(subscriptionDb, 'subscription.rows'),
              );
        final answer = core.derive('subscription.stats', {
          'total': total,
          'hits': hits,
          'subscriptions': subscriptions,
          'sortByName': true,
        });
        final items =
            [
              for (final row in answer['items'] as List? ?? const [])
                _interceptionItemOf((row as Map).cast<String, Object?>()),
            ]..sort((a, b) {
              final byHits = b.hits.compareTo(a.hits);
              return byHits != 0 ? byHits : a.name.compareTo(b.name);
            });

        return SubscriptionInterceptionSnapshot(
          totalRequests: total,
          items: items,
        );
      } on DatabaseException catch (error) {
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
