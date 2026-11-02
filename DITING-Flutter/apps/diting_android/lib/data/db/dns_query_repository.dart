/// Filtered read of the legacy `dns_log` table for the request log page. Per-status SQL stays
/// verbatim: rewrite markers keep rewritten queries out of `passed` and `TCP `/`UDP ` prefixes keep
/// connection lines out.
library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/http_request_repository.dart' show RequestStatus;

class DnsLogRow {
  const DnsLogRow({
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

  final int id;
  final int timestamp;
  final String queryName;
  final int queryType;

  final String result;
  final bool cached;
  final String? message;
  final String? packageName;
  final int? blockSubscriptionId;

  bool get isConnection =>
      queryType == 0 ||
      queryName.startsWith('TCP ') ||
      queryName.startsWith('UDP ') ||
      (message?.contains('blocked_by=connection') ?? false);

  bool get isBlocked =>
      result == 'BLOCKED' ||
      (message?.contains('blocked_by=firewall:') ?? false);

  /// The Chinese markers are the ones legacy rule descriptions emit.
  bool get isRewritten =>
      result == 'REWRITTEN' ||
      (message?.contains('blocked_by=rewrite=') ?? false) ||
      (message?.contains('matched rewrite rule') ?? false) ||
      (message?.contains('复写') ?? false) ||
      (message?.contains('覆写') ?? false);

  /// Display bucket. Connection rows fold into bypassed or blocked; everything unrecognised counts
  /// as error.
  RequestStatus get status {
    if (isConnection) {
      return isBlocked ? RequestStatus.blocked : RequestStatus.bypassed;
    }
    if (isRewritten) return RequestStatus.rewritten;
    return switch (result) {
      'PASSED' => RequestStatus.passed,
      'BLOCKED' => RequestStatus.blocked,
      _ => RequestStatus.error,
    };
  }
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

  final String? app;
  final String? resolved;
  final String? blockedBy;
  final String? error;
  final int? elapsedMs;

  /// Keeps the known keys only; unknown tokens are dropped because the detail sheet labels each
  /// field.
  static DnsLogMessage parse(String? message) {
    if (message == null || message.isEmpty) return const DnsLogMessage();
    String? app;
    String? resolved;
    String? blockedBy;
    String? error;
    int? elapsed;
    for (final raw in message.split(',')) {
      final token = raw.trim();
      final separator = token.indexOf('=');
      if (separator <= 0) continue;
      final key = token.substring(0, separator).trim();
      final value = token.substring(separator + 1).trim();
      if (value.isEmpty) continue;
      switch (key) {
        case 'app':
          app = value;
        case 'resolved':
          resolved = value;
        case 'blocked_by':
          blockedBy = value;
        case 'error':
          error = value;
        case 'elapsed':
          elapsed = int.tryParse(
            value.endsWith('ms') ? value.substring(0, value.length - 2) : value,
          );
      }
    }
    return DnsLogMessage(
      app: app,
      resolved: resolved,
      blockedBy: blockedBy,
      error: error,
      elapsedMs: elapsed,
    );
  }
}

class DnsQueryRepository {
  DnsQueryRepository(this._db);

  final Database _db;

  /// Request count per attributed package; rows without a package are skipped.
  Future<Map<String, int>> countByPackage() async {
    final rows = await _db.rawQuery(
      'SELECT packageName, COUNT(*) AS count FROM dns_log '
      "WHERE packageName IS NOT NULL AND packageName != '' "
      'GROUP BY packageName',
    );
    return {
      for (final row in rows)
        row['packageName'] as String: (row['count'] as num?)?.toInt() ?? 0,
    };
  }

  /// Newest first. The page chips select one bucket at a time, so there is no `IN (...)` path.
  Future<List<DnsLogRow>> recent({
    int limit = 200,
    RequestStatus status = RequestStatus.all,
    String query = '',
    String? packageName,
  }) async {
    final sql = StringBuffer('SELECT * FROM dns_log WHERE 1=1');
    final args = <Object?>[];

    if (packageName != null) {
      sql.write(' AND packageName = ?');
      args.add(packageName);
    }

    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      sql.write(
        ' AND (queryName LIKE ? OR packageName LIKE ? '
        'OR message LIKE ?)',
      );
      final pattern = '%${trimmed.toLowerCase()}%';
      args
        ..add(pattern)
        ..add(pattern)
        ..add(pattern);
    }

    final clause = _statusClause(status);
    if (clause != null) sql.write(clause);

    sql.write(' ORDER BY timestamp DESC LIMIT ${limit < 0 ? 0 : limit}');
    final rows = await _db.rawQuery(sql.toString(), args);
    return [for (final row in rows) _fromRow(row)];
  }

  /// Single-bucket SQL; whitespace included, so it stays verbatim.
  static String? _statusClause(RequestStatus status) => switch (status) {
    RequestStatus.all => null,
    RequestStatus.passed =>
      " AND result = 'PASSED' AND queryType > 0 AND queryName NOT LIKE 'TCP %' "
          "AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR (message NOT "
          "LIKE '%blocked_by=connection%' AND message NOT LIKE "
          "'%blocked_by=rewrite=%' AND message NOT LIKE '%matched rewrite "
          "rule%' AND message NOT LIKE '%复写%' AND message NOT LIKE '%覆写%'))",
    RequestStatus.rewritten =>
      " AND (result = 'REWRITTEN' OR message LIKE '%blocked_by=rewrite=%' OR "
          "message LIKE '%matched rewrite rule%' OR message LIKE '%复写%' OR "
          "message LIKE '%覆写%') AND queryType > 0 AND queryName NOT LIKE "
          "'TCP %' AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR "
          "message NOT LIKE '%blocked_by=connection%')",
    RequestStatus.blocked =>
      " AND (result = 'BLOCKED' OR message LIKE '%blocked_by=firewall:%') "
          "AND (message IS NULL OR (message NOT LIKE '%blocked_by=rewrite=%' "
          "AND message NOT LIKE '%matched rewrite rule%' AND message NOT LIKE "
          "'%复写%' AND message NOT LIKE '%覆写%'))",
    RequestStatus.error =>
      " AND result = 'ERROR' AND queryType > 0 AND queryName NOT LIKE 'TCP %' "
          "AND queryName NOT LIKE 'UDP %' AND (message IS NULL OR (message NOT "
          "LIKE '%blocked_by=connection%' AND message NOT LIKE "
          "'%blocked_by=rewrite=%' AND message NOT LIKE '%matched rewrite "
          "rule%' AND message NOT LIKE '%复写%' AND message NOT LIKE '%覆写%'))",
    RequestStatus.bypassed =>
      " AND (queryType = 0 OR queryName LIKE 'TCP %' OR queryName LIKE "
          "'UDP %' OR message LIKE '%blocked_by=connection%') AND (message IS "
          "NULL OR message NOT LIKE '%blocked_by=firewall:%')",
  };

  static DnsLogRow _fromRow(Map<String, Object?> row) => DnsLogRow(
    id: (row['id'] as num?)?.toInt() ?? 0,
    timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
    queryName: row['queryName'] as String? ?? '',
    queryType: (row['queryType'] as num?)?.toInt() ?? 0,
    result: row['result'] as String? ?? '',
    cached: (row['cached'] as num?)?.toInt() == 1,
    message: row['message'] as String?,
    packageName: row['packageName'] as String?,
    blockSubscriptionId: (row['blockSubscriptionId'] as num?)?.toInt(),
  );
}
