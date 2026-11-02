/// Read access to the legacy `bootstrap_log` table; rows are written natively when a bootstrap IP
/// is probed.
library;

import 'package:sqflite/sqflite.dart';

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

  final String id;
  final String name;
  final String ip;
  final int attempts;
  final int successes;
  final int failures;
  final double? averageElapsedMs;
}

class BootstrapLogRepository {
  BootstrapLogRepository(this._db);

  final Database _db;

  Future<List<BootstrapIpStat>> recentStats({
    Duration window = const Duration(hours: 24),
  }) async {
    final since = DateTime.now().subtract(window).millisecondsSinceEpoch;
    final rows = await _db.rawQuery(
      'SELECT ipId, MAX(ipName) AS ipName, MAX(ip) AS ip, COUNT(*) AS attempts, '
      'COALESCE(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END), 0) AS successes, '
      'COALESCE(SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END), 0) AS failures, '
      'AVG(elapsedMs) AS avgElapsedMs '
      'FROM bootstrap_log WHERE timestamp >= ? GROUP BY ipId ORDER BY attempts DESC',
      [since],
    );
    return [
      for (final row in rows)
        BootstrapIpStat(
          id: row['ipId'] as String? ?? '',
          name: row['ipName'] as String? ?? '',
          ip: row['ip'] as String? ?? '',
          attempts: (row['attempts'] as num?)?.toInt() ?? 0,
          successes: (row['successes'] as num?)?.toInt() ?? 0,
          failures: (row['failures'] as num?)?.toInt() ?? 0,
          averageElapsedMs: (row['avgElapsedMs'] as num?)?.toDouble(),
        ),
    ];
  }
}
