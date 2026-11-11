/// Read/delete access to the legacy `dns_log` table; rows are written natively through
/// [DnsLogWriter]. The statement, the row defaults and the daily counters live in
/// `rust/diting-log-query-core`.
library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/rust_log_query_core.dart';

class DnsLogRecord {
  const DnsLogRecord({
    required this.timestamp,
    required this.domain,
    required this.queryType,
    required this.result,
    required this.cached,
    this.message,
    this.packageName,
  });

  factory DnsLogRecord.fromParsed(Map<String, Object?> row) => DnsLogRecord(
    timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
    domain: row['domain'] as String? ?? '',
    queryType: (row['queryType'] as num?)?.toInt() ?? 1,
    result: row['result'] as String? ?? 'PASSED',
    cached: row['cached'] as bool? ?? false,
    message: row['message'] as String?,
    packageName: row['packageName'] as String?,
  );

  final int timestamp;
  final String domain;
  final int queryType;
  final String result;
  final bool cached;
  final String? message;
  final String? packageName;
}

class DnsLogRepository {
  DnsLogRepository(this._db);

  final Database _db;

  Future<List<DnsLogRecord>> recent({int limit = 200}) async {
    final plan = RustLogQueryCore.instance.plan('dns.recent', {'limit': limit});
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('dns.record', rows))
        DnsLogRecord.fromParsed(row),
    ];
  }

  /// PASSED and REWRITTEN count as passed. Aggregated in SQL: the dashboard re-runs this every 10 s,
  /// and shipping every row of a busy day (100k+) over the platform channel to regex it in Dart
  /// was the most expensive read in the app. `elapsed=` parsing mirrors [elapsedMsOf]: SQLite's
  /// integer cast stops at the `ms` suffix.
  Future<DnsLogDailyStats> dailyStats({DateTime? since}) async {
    final start = (since ?? _startOfToday()).millisecondsSinceEpoch;
    final plan = RustLogQueryCore.instance.plan('dns.daily', {'since': start});
    final rows = await _db.rawQuery(plan.sql, plan.args);
    final parsed = RustLogQueryCore.instance.rows('dns.daily', rows);
    return parsed.isEmpty
        ? const DnsLogDailyStats.empty()
        : DnsLogDailyStats.fromParsed(parsed.first);
  }

  /// Reads `elapsed=123ms`; the writer only emits it for positive durations.
  static int? elapsedMsOf(String? message) =>
      (RustLogQueryCore.instance.classify('dnsElapsed', {
            'message': message,
          })['value']
          as num?)
      ?.toInt();

  Future<int> clear() => _db.delete('dns_log');

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

class DnsLogDailyStats {
  const DnsLogDailyStats({
    required this.total,
    required this.passed,
    required this.blocked,
    required this.error,
    required this.cached,
    this.averageLatencyMs = 0,
    this.latencySamples = 0,
    this.cacheHitRate = 0,
  });

  factory DnsLogDailyStats.fromParsed(Map<String, Object?> row) =>
      DnsLogDailyStats(
        total: (row['total'] as num?)?.toInt() ?? 0,
        passed: (row['passed'] as num?)?.toInt() ?? 0,
        blocked: (row['blocked'] as num?)?.toInt() ?? 0,
        error: (row['error'] as num?)?.toInt() ?? 0,
        cached: (row['cached'] as num?)?.toInt() ?? 0,
        averageLatencyMs: (row['averageLatencyMs'] as num?)?.toInt() ?? 0,
        latencySamples: (row['latencySamples'] as num?)?.toInt() ?? 0,
        cacheHitRate: (row['cacheHitRate'] as num?)?.toDouble() ?? 0,
      );

  const DnsLogDailyStats.empty()
    : total = 0,
      passed = 0,
      blocked = 0,
      error = 0,
      cached = 0,
      averageLatencyMs = 0,
      latencySamples = 0,
      cacheHitRate = 0;

  final int total;
  final int passed;
  final int blocked;
  final int error;
  final int cached;

  /// Mean `elapsed=` over timed rows only; rule-blocked rows carry no timing.
  final int averageLatencyMs;

  final int latencySamples;

  /// Mirrors engine `hitRatio`: errors join the denominator (cache lookup precedes upstream
  /// failure) and a stale-while-revalidate reply counts as a stale hit.
  final double cacheHitRate;

  /// The shape the overview aggregate consumes.
  Map<String, Object?> toKernel() => {
    'total': total,
    'passed': passed,
    'blocked': blocked,
    'error': error,
    'cached': cached,
    'averageLatencyMs': averageLatencyMs,
    'latencySamples': latencySamples,
    'cacheHitRate': cacheHitRate,
  };
}
