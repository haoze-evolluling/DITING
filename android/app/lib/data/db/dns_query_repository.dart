/// Filtered read of the legacy `dns_log` table for the request log page. Per-status SQL, bucket
/// classification and the `message` parse live in `rust/diting-log-query-core`.
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

  /// A page row already classified by the kernel; no second FFI round trip on the getters.
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
    ).._classification = {
      'isConnection': row['isConnection'],
      'isBlocked': row['isBlocked'],
      'isRewritten': row['isRewritten'],
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

  /// Kernel classification, filled eagerly by [DnsLogRow.fromParsed] and lazily for rows the
  /// tests construct by hand.
  Map<String, Object?>? _classification;

  Map<String, Object?> get _flags => _classification ??= RustLogQueryCore.instance
      .classify('dnsRow', {
        'queryType': queryType,
        'queryName': queryName,
        'result': result,
        'cached': cached,
        'message': message,
      });

  bool get isConnection => _flags['isConnection'] as bool? ?? false;

  bool get isBlocked => _flags['isBlocked'] as bool? ?? false;

  /// The Chinese markers are the ones legacy rule descriptions emit.
  bool get isRewritten => _flags['isRewritten'] as bool? ?? false;

  /// Display bucket. Connection rows fold into bypassed or blocked; everything unrecognised counts
  /// as error.
  RequestStatus get status => switch (_flags['status']) {
    'passed' => RequestStatus.passed,
    'rewritten' => RequestStatus.rewritten,
    'blocked' => RequestStatus.blocked,
    'bypassed' => RequestStatus.bypassed,
    _ => RequestStatus.error,
  };

  /// Parsed `dns_log.message` fields, already tokenised by the kernel.
  DnsLogMessage get messageFields => DnsLogMessage.fromParsed(
    (_flags['messageFields'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  /// Raw fields for a kernel aggregate; classification is recomputed there.
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

/// Parsed `dns_log.message` (`app=.., resolved=.., blocked_by=.., error=.., elapsed=NNms`); each
/// token splits on its first `=`.
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

  /// Keeps the known keys only; unknown tokens are dropped because the detail sheet labels each
  /// field.
  static DnsLogMessage parse(String? message) => DnsLogMessage.fromParsed(
    RustLogQueryCore.instance.classify('dnsMessage', {'message': message}),
  );
}

class DnsQueryRepository {
  DnsQueryRepository(this._db);

  final Database _db;

  /// Request count per attributed package; rows without a package are skipped.
  Future<Map<String, int>> countByPackage() async {
    final plan = RustLogQueryCore.instance.plan('dns.query.countByPackage');
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return {
      for (final row in RustLogQueryCore.instance.rows('packageCount', rows))
        row['packageName'] as String:
            (row['count'] as num?)?.toInt() ?? 0,
    };
  }

  /// Newest first. The page chips select one bucket at a time, so there is no `IN (...)` path.
  Future<List<DnsLogRow>> recent({
    int limit = 200,
    RequestStatus status = RequestStatus.all,
    String query = '',
    String? packageName,
    int? before,
  }) async {
    final plan = RustLogQueryCore.instance.plan('dns.query.recent', {
      'limit': limit,
      'status': _statusToken(status),
      'query': query,
      if (packageName != null) 'packageName': packageName,
      // Inclusive `timestamp` cursor: the merged feed pages by time, not by row offset.
      if (before != null) 'before': before,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('dns.row', rows))
        DnsLogRow.fromParsed(row),
    ];
  }

  /// Newest-first rows for a CSV export, bounded by [limit] and an optional `[since, until]`
  /// window.
  ///
  /// [packages] narrows to those packages; an empty set means every app. The statement itself
  /// lives in `dns.query.export`, so the status clauses stay shared with the list page.
  Future<List<DnsLogRow>> export({
    int limit = 1000,
    RequestStatus status = RequestStatus.all,
    int? since,
    int? until,
    Set<String> packages = const {},
  }) async {
    final plan = RustLogQueryCore.instance.plan('dns.query.export', {
      'limit': limit,
      'status': _statusToken(status),
      if (since != null) 'since': since,
      if (until != null) 'until': until,
      if (packages.isNotEmpty) 'packages': packages.toList(),
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('dns.row', rows))
        DnsLogRow.fromParsed(row),
    ];
  }

  /// The kernel's spelling of a bucket; `all` adds no clause.
  static String _statusToken(RequestStatus status) => switch (status) {
    RequestStatus.all => 'all',
    RequestStatus.passed => 'passed',
    RequestStatus.rewritten => 'rewritten',
    RequestStatus.blocked => 'blocked',
    RequestStatus.error => 'error',
    RequestStatus.bypassed => 'bypassed',
  };
}
