/// Read access to the legacy `dns_cache` table; `DnsCacheMirror` copies the engine's in-memory
/// LRU into it every 10 s, so rows lag the engine by at most one publish interval. The statement
/// and the TTL arithmetic live in `rust/diting-log-query-core`.
library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/rust_log_query_core.dart';

class DnsCacheRecord {
  const DnsCacheRecord({
    required this.domain,
    required this.queryType,
    required this.expiresAt,
    required this.hitCount,
    required this.originalTtlSeconds,
    required this.responseSize,
    this.remainingTtlFromKernel,
  });

  factory DnsCacheRecord.fromParsed(Map<String, Object?> row) =>
      DnsCacheRecord(
        domain: row['domain'] as String? ?? '',
        queryType: (row['queryType'] as num?)?.toInt() ?? 1,
        expiresAt: (row['expiresAt'] as num?)?.toInt() ?? 0,
        hitCount: (row['hitCount'] as num?)?.toInt() ?? 0,
        originalTtlSeconds: (row['originalTtlSeconds'] as num?)?.toInt() ?? 0,
        responseSize: (row['responseSize'] as num?)?.toInt() ?? 0,
        remainingTtlFromKernel: (row['remainingTtlSeconds'] as num?)?.toInt(),
      );

  final String domain;
  final int queryType;
  final int expiresAt;
  final int hitCount;
  final int originalTtlSeconds;
  final int responseSize;

  /// Set by [DnsCacheRepository.entries] from the statement's `nowMs`; null on hand-built rows,
  /// which fall back to the wall clock.
  final int? remainingTtlFromKernel;

  int get remainingTtlSeconds {
    final fromKernel = remainingTtlFromKernel;
    if (fromKernel != null) return fromKernel;
    final remaining = expiresAt - DateTime.now().millisecondsSinceEpoch;
    return remaining <= 0 ? 0 : remaining ~/ 1000;
  }

  /// The shape the overview aggregate consumes.
  Map<String, Object?> toKernel() => {
    'queryName': domain,
    'queryType': queryType,
    'remainingTtlSeconds': remainingTtlSeconds,
    'responseSize': responseSize,
    'hitCount': hitCount,
  };
}

class DnsCacheRepository {
  DnsCacheRepository(this._db);

  final Database _db;

  Future<List<DnsCacheRecord>> entries({int limit = 200}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final plan = RustLogQueryCore.instance.plan('cache.entries', {
      'now': now,
      'limit': limit,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows(
        'cache.entry',
        rows,
        nowMs: now,
      ))
        DnsCacheRecord.fromParsed(row),
    ];
  }

  Future<int> countUnexpired() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final plan = RustLogQueryCore.instance.plan('cache.count', {'now': now});
    final rows = await _db.rawQuery(plan.sql, plan.args);
    final parsed = RustLogQueryCore.instance.rows('count', rows);
    return parsed.isEmpty ? 0 : (parsed.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Lifetime hits over the whole table, expired rows included.
  Future<int> totalHitCount() async {
    final plan = RustLogQueryCore.instance.plan('cache.hits');
    final rows = await _db.rawQuery(plan.sql, plan.args);
    final parsed = RustLogQueryCore.instance.rows('count', rows);
    return parsed.isEmpty ? 0 : (parsed.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Average cached response size, used by the "saved bytes" estimate.
  Future<double> averageResponseSize() async {
    final plan = RustLogQueryCore.instance.plan('cache.avgSize');
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return rows.isEmpty ? 0.0 : (rows.first['n'] as num?)?.toDouble() ?? 0.0;
  }
}
