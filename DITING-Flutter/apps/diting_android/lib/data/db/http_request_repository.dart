/// Read/delete access to the legacy `http_request_log` table; rows are written natively and the
/// filter clauses mirror the legacy repository.
library;

import 'package:sqflite/sqflite.dart';

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
  });

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

  /// Bucket for this record; unlisted outcomes count as `error`, including failure types the engine
  /// may add later.
  RequestStatus get status => statusOfOutcome(outcome);
}

RequestStatus statusOfOutcome(String outcome) => switch (outcome) {
  'allowed' => RequestStatus.passed,
  'rewritten' => RequestStatus.rewritten,
  'blocked' || 'invalid' => RequestStatus.blocked,
  'passthrough' ||
  'bypassed' ||
  'unsupported_protocol' ||
  'resource_bypass' => RequestStatus.bypassed,
  _ => RequestStatus.error,
};

class HttpRequestDailyStats {
  const HttpRequestDailyStats({required this.total, required this.byOutcome});

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
  }) async {
    final trimmed = query.trim();
    final args = <Object?>[];
    final sql = StringBuffer('SELECT * FROM http_request_log WHERE 1=1');

    if (packageName != null) {
      sql.write(' AND packageName = ?');
      args.add(packageName);
    }

    if (trimmed.isNotEmpty) {
      sql.write(
        ' AND (authority LIKE ? OR packageName LIKE ? '
        'OR matchedRule LIKE ?)',
      );
      final pattern = '%${trimmed.toLowerCase()}%';
      args
        ..add(pattern)
        ..add(pattern)
        ..add(pattern);
    }

    switch (status) {
      case RequestStatus.all:
        break;
      case RequestStatus.passed:
        sql.write(" AND outcome = 'allowed'");
      case RequestStatus.rewritten:
        sql.write(" AND outcome = 'rewritten'");
      case RequestStatus.blocked:
        sql.write(" AND outcome IN ('blocked', 'invalid')");
      case RequestStatus.error:
        sql.write(
          " AND outcome NOT IN ('allowed', 'rewritten', 'blocked', 'invalid', "
          "'passthrough', 'bypassed', 'unsupported_protocol', "
          "'resource_bypass')",
        );
      case RequestStatus.bypassed:
        sql.write(
          " AND outcome IN ('passthrough', 'bypassed', 'unsupported_protocol', "
          "'resource_bypass')",
        );
    }

    sql.write(' ORDER BY timestamp DESC LIMIT ${limit < 0 ? 0 : limit}');
    final rows = await _db.rawQuery(sql.toString(), args);
    return [for (final row in rows) _fromRow(row)];
  }

  /// One scan yields both the groups and their sum, so the total and the buckets can never disagree
  /// across midnight.
  Future<HttpRequestDailyStats> dailyStats({DateTime? since}) async {
    final start = (since ?? _startOfToday()).millisecondsSinceEpoch;
    final rows = await _db.rawQuery(
      'SELECT outcome, COUNT(*) AS count FROM http_request_log '
      'WHERE timestamp >= ? GROUP BY outcome',
      [start],
    );
    final byOutcome = <String, int>{};
    var total = 0;
    for (final row in rows) {
      final count = (row['count'] as num?)?.toInt() ?? 0;
      byOutcome[row['outcome'] as String? ?? ''] = count;
      total += count;
    }
    return HttpRequestDailyStats(total: total, byOutcome: byOutcome);
  }

  /// Request count per attributed package; rows without a package are skipped.
  Future<Map<String, int>> countByPackage() async {
    final rows = await _db.rawQuery(
      'SELECT packageName, COUNT(*) AS count FROM http_request_log '
      "WHERE packageName != '' GROUP BY packageName",
    );
    return {
      for (final row in rows)
        row['packageName'] as String: (row['count'] as num?)?.toInt() ?? 0,
    };
  }

  Future<int> clearAll() => _db.delete('http_request_log');

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static HttpRequestRecord _fromRow(Map<String, Object?> row) =>
      HttpRequestRecord(
        id: (row['id'] as num?)?.toInt() ?? 0,
        timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
        packageName: row['packageName'] as String? ?? '',
        protocol: row['protocol'] as String? ?? '',
        outcome: row['outcome'] as String? ?? '',
        authority: row['authority'] as String?,
        matchedRule: row['matchedRule'] as String?,
        blockSubscriptionId: (row['blockSubscriptionId'] as num?)?.toInt(),
      );
}
