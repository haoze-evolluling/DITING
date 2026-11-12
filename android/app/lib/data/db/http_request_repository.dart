/// Read/delete access to the legacy `http_request_log` table; rows are written natively. The SQL,
/// outcome buckets and row defaults live in `rust/diting-log-query-core`.
library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/rust_log_query_core.dart';

/// Outcome buckets: `rewritten` and `bypassed` are neither success, blocked nor failed.
enum RequestStatus {
  all('全部', '显示所有请求记录'),
  passed('通过', '请求正常放行，未命中拦截规则'),
  rewritten('覆写', '请求命中了覆写规则，并返回覆写后的结果'),
  blocked('过滤', '请求命中了过滤规则并被拦截'),
  error('失败', '请求解析或处理失败'),
  bypassed('旁路', '请求未被读取或过滤，直接建立连接');

  const RequestStatus(this.label, this.explanation);

  final String label;
  final String explanation;
}

enum RequestSource {
  all('全部'),
  dns('DNS'),
  https('HTTPS');

  const RequestSource(this.label);

  final String label;
}

class HttpRequestRecord {
  const HttpRequestRecord({
    required this.id,
    required this.timestamp,
    required this.packageName,
    required this.protocol,
    required this.outcome,
    this.authority,
    this.matchedRule,
    this.blockSubscriptionId,
    this.statusToken,
  });

  factory HttpRequestRecord.fromParsed(Map<String, Object?> row) =>
      HttpRequestRecord(
        id: (row['id'] as num?)?.toInt() ?? 0,
        timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
        packageName: row['packageName'] as String? ?? '',
        protocol: row['protocol'] as String? ?? '',
        outcome: row['outcome'] as String? ?? '',
        authority: row['authority'] as String?,
        matchedRule: row['matchedRule'] as String?,
        blockSubscriptionId: (row['blockSubscriptionId'] as num?)?.toInt(),
        statusToken: row['status'] as String?,
      );

  final int id;
  final int timestamp;
  final String packageName;

  /// Null when no authority is known, e.g. an early TLS failure.
  final String? authority;

  final String protocol;

  /// Raw stored value, not a bucket; see [statusOfOutcome].
  final String outcome;
  final String? matchedRule;
  final int? blockSubscriptionId;

  /// Kernel bucket, present on rows read from the database.
  final String? statusToken;

  /// Bucket for this record; unlisted outcomes count as `error`, including failure types the engine
  /// may add later.
  RequestStatus get status => statusToken == null
      ? statusOfOutcome(outcome)
      : _statusOfToken(statusToken!);

  /// Raw fields for a kernel aggregate; classification is recomputed there.
  Map<String, Object?> toKernelRow() => {
    'id': id,
    'timestamp': timestamp,
    'packageName': packageName,
    'protocol': protocol,
    'outcome': outcome,
    'authority': authority,
    'matchedRule': matchedRule,
    'blockSubscriptionId': blockSubscriptionId,
  };
}

RequestStatus _statusOfToken(String token) => switch (token) {
  'passed' => RequestStatus.passed,
  'rewritten' => RequestStatus.rewritten,
  'blocked' => RequestStatus.blocked,
  'bypassed' => RequestStatus.bypassed,
  _ => RequestStatus.error,
};

RequestStatus statusOfOutcome(String outcome) => _statusOfToken(
  RustLogQueryCore.instance.classify('httpRequestStatus', {
        'outcome': outcome,
      })['status']
      as String? ??
      'error',
);

class HttpRequestDailyStats {
  const HttpRequestDailyStats({required this.total, required this.byOutcome});

  factory HttpRequestDailyStats.fromParsed(Map<String, Object?> row) =>
      HttpRequestDailyStats(
        total: (row['total'] as num?)?.toInt() ?? 0,
        byOutcome: {
          for (final entry
              in (row['byOutcome'] as Map?)?.entries ?? const <MapEntry>[])
            entry.key as String: (entry.value as num?)?.toInt() ?? 0,
        },
      );

  const HttpRequestDailyStats.empty() : total = 0, byOutcome = const {};

  final int total;

  /// Keys are raw outcome values, not buckets.
  final Map<String, int> byOutcome;

  int countFor(RequestStatus status) {
    if (status == RequestStatus.all) return total;
    var count = 0;
    for (final entry in byOutcome.entries) {
      if (statusOfOutcome(entry.key) == status) count += entry.value;
    }
    return count;
  }

  /// The shape the overview aggregate consumes.
  Map<String, Object?> toKernel() => {'total': total, 'byOutcome': byOutcome};
}

class HttpRequestRepository {
  HttpRequestRepository(this._db);

  final Database _db;

  /// Lower-cased: `LIKE` is ASCII case-insensitive and `authority` is stored lower-cased, so a
  /// mixed-case `matchedRule` is the only miss.
  Future<List<HttpRequestRecord>> recent({
    int limit = 200,
    RequestStatus status = RequestStatus.all,
    String query = '',
    String? packageName,
    int? before,
  }) async {
    final plan = RustLogQueryCore.instance.plan('http.query.recent', {
      'limit': limit,
      'status': _statusToken(status),
      'query': query,
      if (packageName != null) 'packageName': packageName,
      // Inclusive `timestamp` cursor: the merged feed pages by time, not by row offset.
      if (before != null) 'before': before,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('http.row', rows))
        HttpRequestRecord.fromParsed(row),
    ];
  }

  /// One scan yields both the groups and their sum, so the total and the buckets can never disagree
  /// across midnight.
  Future<HttpRequestDailyStats> dailyStats({DateTime? since}) async {
    final start = (since ?? _startOfToday()).millisecondsSinceEpoch;
    final plan = RustLogQueryCore.instance.plan('http.daily', {'since': start});
    final rows = await _db.rawQuery(plan.sql, plan.args);
    final parsed = RustLogQueryCore.instance.rows('http.daily', rows);
    return parsed.isEmpty
        ? const HttpRequestDailyStats.empty()
        : HttpRequestDailyStats.fromParsed(parsed.first);
  }

  /// Request count per attributed package; rows without a package are skipped.
  Future<Map<String, int>> countByPackage() async {
    final plan = RustLogQueryCore.instance.plan('http.query.countByPackage');
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return {
      for (final row in RustLogQueryCore.instance.rows('packageCount', rows))
        row['packageName'] as String:
            (row['count'] as num?)?.toInt() ?? 0,
    };
  }

  /// Newest-first rows for a CSV export, bounded by [limit] and an optional `[since, until]`
  /// window.
  ///
  /// [packages] narrows to those packages; an empty set means every app. The statement itself
  /// lives in `http.query.export`, so the status clauses stay shared with the list page.
  Future<List<HttpRequestRecord>> export({
    int limit = 1000,
    RequestStatus status = RequestStatus.all,
    int? since,
    int? until,
    Set<String> packages = const {},
  }) async {
    final plan = RustLogQueryCore.instance.plan('http.query.export', {
      'limit': limit,
      'status': _statusToken(status),
      if (since != null) 'since': since,
      if (until != null) 'until': until,
      if (packages.isNotEmpty) 'packages': packages.toList(),
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('http.row', rows))
        HttpRequestRecord.fromParsed(row),
    ];
  }

  Future<int> clearAll() => _db.delete('http_request_log');

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static String _statusToken(RequestStatus status) => switch (status) {
    RequestStatus.all => 'all',
    RequestStatus.passed => 'passed',
    RequestStatus.rewritten => 'rewritten',
    RequestStatus.blocked => 'blocked',
    RequestStatus.error => 'error',
    RequestStatus.bypassed => 'bypassed',
  };
}
