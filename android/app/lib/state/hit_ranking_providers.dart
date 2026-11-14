/// R2 命中统计/归因的数据层：把 `dns_log` 里被拦截的记录按域名、按命中原因聚合出 Top N。
///
/// 聚合 SQL（含从 `message` 的 `blocked_by=` 抽原因）在 `rust/diting-log-query-core` 里，
/// 这里只取数并映射成模型，避免第二份归类逻辑。因为不新建表，对既有库升级是安全的。
library;

import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 复用 [LogStatsRange] 的今日 / 近 7 天 / 全部时间窗。
class HitRankingRangeNotifier extends Notifier<LogStatsRange> {
  @override
  LogStatsRange build() => LogStatsRange.today;

  void select(LogStatsRange range) {
    if (state == range) return;
    state = range;
  }
}

final hitRankingRangeProvider =
    NotifierProvider<HitRankingRangeNotifier, LogStatsRange>(
      HitRankingRangeNotifier.new,
    );

/// 一行排行：标签（域名或原因）与命中次数。
class HitRankRow {
  const HitRankRow({required this.label, required this.count});

  final String label;
  final int count;
}

class HitRankingSnapshot {
  const HitRankingSnapshot({
    required this.domains,
    required this.reasons,
    required this.totalBlocked,
  });

  const HitRankingSnapshot.empty()
    : domains = const [],
      reasons = const [],
      totalBlocked = 0;

  final List<HitRankRow> domains;
  final List<HitRankRow> reasons;

  /// 同一时间窗内的总拦截数（排行的分母）。
  final int totalBlocked;

  bool get isEmpty => domains.isEmpty && reasons.isEmpty;
}

final hitRankingProvider = FutureProvider<HitRankingSnapshot>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final range = ref.watch(hitRankingRangeProvider);
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const HitRankingSnapshot.empty();
  final since = range.startOf(DateTime.now())?.millisecondsSinceEpoch ?? 0;
  final core = RustLogQueryCore.instance;

  Future<List<Map<String, Object?>>> raw(
    String name,
    Map<String, Object?> params,
  ) {
    final plan = core.plan(name, params);
    return db.rawQuery(plan.sql, plan.args);
  }

  List<HitRankRow> parse(List<Map<String, Object?>> rows, String key) => [
    for (final row in rows)
      if (((row[key] as String?) ?? '').isNotEmpty)
        HitRankRow(
          label: row[key]! as String,
          count: (row['count'] as num?)?.toInt() ?? 0,
        ),
  ];

  final domains = parse(
    await raw('dns.topDomains', {'since': since, 'limit': 20}),
    'domain',
  );
  final reasons = parse(
    await raw('dns.topReasons', {'since': since, 'limit': 20}),
    'reason',
  );
  final totalRows = await raw('dns.blockedCount', {'since': since});
  final total = totalRows.isEmpty
      ? 0
      : (totalRows.first['n'] as num?)?.toInt() ?? 0;
  return HitRankingSnapshot(
    domains: domains,
    reasons: reasons,
    totalBlocked: total,
  );
});
