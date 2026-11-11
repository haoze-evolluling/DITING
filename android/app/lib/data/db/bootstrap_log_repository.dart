/// Read access to the legacy `bootstrap_log` table; rows are written natively when a bootstrap IP
/// is probed. The statement and row defaults live in `rust/diting-log-query-core`.
library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/rust_log_query_core.dart';

class BootstrapIpStat {
  const BootstrapIpStat({
    required this.id,
    required this.name,
    required this.ip,
    required this.attempts,
    required this.successes,
    required this.failures,
    required this.averageElapsedMs,
  });

  factory BootstrapIpStat.fromParsed(Map<String, Object?> row) =>
      BootstrapIpStat(
        id: row['id'] as String? ?? '',
        name: row['name'] as String? ?? '',
        ip: row['ip'] as String? ?? '',
        attempts: (row['attempts'] as num?)?.toInt() ?? 0,
        successes: (row['successes'] as num?)?.toInt() ?? 0,
        failures: (row['failures'] as num?)?.toInt() ?? 0,
        averageElapsedMs: (row['averageElapsedMs'] as num?)?.toDouble(),
      );

  final String id;
  final String name;
  final String ip;
  final int attempts;
  final int successes;
  final int failures;
  final double? averageElapsedMs;

  /// The shape the overview/statistics aggregates consume.
  Map<String, Object?> toKernel() => {
    'name': name,
    'ip': ip,
    'attempts': attempts,
    'successes': successes,
    'failures': failures,
    'averageElapsedMs': averageElapsedMs,
  };
}

class BootstrapLogRepository {
  BootstrapLogRepository(this._db);

  final Database _db;

  Future<List<BootstrapIpStat>> recentStats({
    Duration window = const Duration(hours: 24),
  }) async {
    final since = DateTime.now().subtract(window).millisecondsSinceEpoch;
    final plan = RustLogQueryCore.instance.plan('bootstrap.recent', {
      'since': since,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('bootstrap.stat', rows))
        BootstrapIpStat.fromParsed(row),
    ];
  }
}
