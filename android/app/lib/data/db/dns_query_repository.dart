library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/http_request_repository.dart'
    show RequestStatus;
import 'package:diting_android/data/db/rust_log_query_core.dart';

class DnsLogRow {
  DnsLogRow({
    required this.id,
    required this.timestamp,
    required this.queryName,
    required this.queryType,
    required this.result,
    required this.cached,
    this.message,
    this.packageName,
    this.blockSubscriptionId,
  });

  factory DnsLogRow.fromParsed(Map<String, Object?> row) {
    final message = row['message'] as String?;
    return DnsLogRow(
        id: (row['id'] as num?)?.toInt() ?? 0,
        timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
        queryName: row['queryName'] as String? ?? '',
        queryType: (row['queryType'] as num?)?.toInt() ?? 0,
        result: row['result'] as String? ?? '',
        cached: row['cached'] as bool? ?? false,
        message: message,
        packageName: row['packageName'] as String?,
        blockSubscriptionId: (row['blockSubscriptionId'] as num?)?.toInt(),
      )
      .._classification = {
        'isConnection': row['isConnection'],
        'status': row['status'],
        'messageFields': row['messageFields'],
      };
  }

  final int id;
  final int timestamp;
  final String queryName;
  final int queryType;

  final String result;
  final bool cached;
  final String? message;
  final String? packageName;
  final int? blockSubscriptionId;

  Map<String, Object?>? _classification;

  Map<String, Object?> get _flags =>
      _classification ??= RustLogQueryCore.instance.classify('dnsRow', {
        'queryType': queryType,
        'queryName': queryName,
        'result': result,
        'cached': cached,
        'message': message,
      });

  bool get isConnection => _flags['isConnection'] as bool? ?? false;

  RequestStatus get status => switch (_flags['status']) {
    'passed' => RequestStatus.passed,
    'rewritten' => RequestStatus.rewritten,
    'blocked' => RequestStatus.blocked,
    'bypassed' => RequestStatus.bypassed,
    _ => RequestStatus.error,
  };

  DnsLogMessage get messageFields => DnsLogMessage.fromParsed(
    (_flags['messageFields'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  Map<String, Object?> toKernelRow() => {
    'id': id,
    'timestamp': timestamp,
    'queryName': queryName,
    'queryType': queryType,
    'result': result,
    'cached': cached ? 1 : 0,
    'message': message,
    'packageName': packageName,
    'blockSubscriptionId': blockSubscriptionId,
  };
}

class DnsLogMessage {
  const DnsLogMessage({
    this.app,
    this.resolved,
    this.blockedBy,
    this.error,
    this.elapsedMs,
  });

  factory DnsLogMessage.fromParsed(Map<String, Object?> row) => DnsLogMessage(
    app: row['app'] as String?,
    resolved: row['resolved'] as String?,
    blockedBy: row['blockedBy'] as String?,
    error: row['error'] as String?,
    elapsedMs: (row['elapsedMs'] as num?)?.toInt(),
  );

  final String? app;
  final String? resolved;
  final String? blockedBy;
  final String? error;
  final int? elapsedMs;

  static DnsLogMessage parse(String? message) => DnsLogMessage.fromParsed(
    RustLogQueryCore.instance.classify('dnsMessage', {'message': message}),
  );
}

class DnsQueryRepository {
  DnsQueryRepository(this._db);

  final Database _db;

  Future<Map<String, int>> countByPackage() async {
    final plan = RustLogQueryCore.instance.plan('dns.query.countByPackage');
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return {
      for (final row in RustLogQueryCore.instance.rows('packageCount', rows))
        row['packageName'] as String: (row['count'] as num?)?.toInt() ?? 0,
    };
  }

  Future<List<DnsLogRow>> recent({
    int limit = 200,
    RequestStatus status = RequestStatus.all,
    String query = '',
    String? packageName,
    int? before,
  }) async {
    final plan = RustLogQueryCore.instance.plan('dns.query.recent', {
      'limit': limit,
      'status': status.token,
      'query': query,
      'packageName': ?packageName,
      'before': ?before,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('dns.row', rows))
        DnsLogRow.fromParsed(row),
    ];
  }

  Future<List<DnsLogRow>> export({
    int limit = 1000,
    RequestStatus status = RequestStatus.all,
    int? since,
    int? until,
    Set<String> packages = const {},
  }) async {
    final plan = RustLogQueryCore.instance.plan('dns.query.export', {
      'limit': limit,
      'status': status.token,
      'since': ?since,
      'until': ?until,
      if (packages.isNotEmpty) 'packages': packages.toList(),
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('dns.row', rows))
        DnsLogRow.fromParsed(row),
    ];
  }
}
