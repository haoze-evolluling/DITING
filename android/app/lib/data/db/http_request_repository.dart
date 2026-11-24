library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/rust_log_query_core.dart';

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

  String get token => switch (this) {
    RequestStatus.all => 'all',
    RequestStatus.passed => 'passed',
    RequestStatus.rewritten => 'rewritten',
    RequestStatus.blocked => 'blocked',
    RequestStatus.error => 'error',
    RequestStatus.bypassed => 'bypassed',
  };
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

  final String? authority;

  final String protocol;

  final String outcome;
  final String? matchedRule;
  final int? blockSubscriptionId;

  final String? statusToken;

  RequestStatus get status => statusToken == null
      ? statusOfOutcome(outcome)
      : _statusOfToken(statusToken!);

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

  final Map<String, int> byOutcome;

  Map<String, Object?> toKernel() => {'total': total, 'byOutcome': byOutcome};
}

class HttpRequestRepository {
  HttpRequestRepository(this._db);

  final Database _db;

  Future<List<HttpRequestRecord>> recent({
    int limit = 200,
    RequestStatus status = RequestStatus.all,
    String query = '',
    String? packageName,
    int? before,
  }) async {
    final plan = RustLogQueryCore.instance.plan('http.query.recent', {
      'limit': limit,
      'status': status.token,
      'query': query,
      'packageName': ?packageName,
      'before': ?before,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('http.row', rows))
        HttpRequestRecord.fromParsed(row),
    ];
  }

  Future<HttpRequestDailyStats> dailyStats({DateTime? since}) async {
    final start = (since ?? _startOfToday()).millisecondsSinceEpoch;
    final plan = RustLogQueryCore.instance.plan('http.daily', {'since': start});
    final rows = await _db.rawQuery(plan.sql, plan.args);
    final parsed = RustLogQueryCore.instance.rows('http.daily', rows);
    return parsed.isEmpty
        ? const HttpRequestDailyStats.empty()
        : HttpRequestDailyStats.fromParsed(parsed.first);
  }

  Future<Map<String, int>> countByPackage() async {
    final plan = RustLogQueryCore.instance.plan('http.query.countByPackage');
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return {
      for (final row in RustLogQueryCore.instance.rows('packageCount', rows))
        row['packageName'] as String: (row['count'] as num?)?.toInt() ?? 0,
    };
  }

  Future<List<HttpRequestRecord>> export({
    int limit = 1000,
    RequestStatus status = RequestStatus.all,
    int? since,
    int? until,
    Set<String> packages = const {},
  }) async {
    final plan = RustLogQueryCore.instance.plan('http.query.export', {
      'limit': limit,
      'status': status.token,
      'since': ?since,
      'until': ?until,
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
}
