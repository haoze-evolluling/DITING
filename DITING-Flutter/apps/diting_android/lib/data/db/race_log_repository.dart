/// Read/delete access to the legacy `dns_race_log` table; rows are written natively and provider
/// names are resolved in Dart, since native code only knows the ids.
library;

import 'package:sqflite/sqflite.dart';

class RaceLogRecord {
  const RaceLogRecord({
    required this.timestamp,
    required this.queryName,
    required this.strategy,
    required this.providerCount,
    required this.success,
    required this.elapsedMs,
    this.winnerProviderId,
    this.winnerElapsedMs,
    this.message,
  });

  final int timestamp;
  final String queryName;
  final String strategy;
  final int providerCount;
  final bool success;
  final int elapsedMs;
  final String? winnerProviderId;
  final int? winnerElapsedMs;
  final String? message;
}

class RaceRankingEntry {
  const RaceRankingEntry({
    required this.providerId,
    required this.wins,
    required this.averageLatencyMs,
  });

  final String providerId;
  final int wins;
  final int averageLatencyMs;
}

/// [primaryWins] only matters for `smart_prediction`: successful requests it won.
class RaceStrategyStatRow {
  const RaceStrategyStatRow({
    required this.strategy,
    required this.requests,
    required this.successes,
    required this.failures,
    required this.averageElapsedMs,
    required this.fallbackUses,
    required this.fallbackSuccesses,
    required this.primaryWins,
  });

  final String strategy;
  final int requests;
  final int successes;
  final int failures;
  final double averageElapsedMs;
  final int fallbackUses;
  final int fallbackSuccesses;
  final int primaryWins;

  double get successRate => requests == 0 ? 0 : successes / requests;
  double get primaryWinRate => requests == 0 ? 0 : primaryWins / requests;
}

class RaceSmartSelectionRow {
  const RaceSmartSelectionRow({
    required this.providerId,
    required this.selectedCount,
    required this.selectedSuccesses,
    required this.averageElapsedMs,
  });

  final String providerId;
  final int selectedCount;
  final int selectedSuccesses;
  final double averageElapsedMs;

  double get selectedSuccessRate =>
      selectedCount == 0 ? 0 : selectedSuccesses / selectedCount;
}

class RaceLogSummary {
  const RaceLogSummary({
    required this.requests,
    required this.successes,
    required this.failures,
    required this.averageLatencyMs,
  });

  const RaceLogSummary.empty()
    : requests = 0,
      successes = 0,
      failures = 0,
      averageLatencyMs = 0;

  final int requests;
  final int successes;
  final int failures;
  final int averageLatencyMs;
}

class RaceLogRepository {
  RaceLogRepository(this._db);

  final Database _db;

  Future<List<RaceLogRecord>> recent({int limit = 100}) async {
    final rows = await _db.query(
      'dns_race_log',
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
    );
    return [for (final row in rows) _fromRow(row)];
  }

  /// Wins are rows where this provider produced the winning response; failures are not pinned on
  /// the provider that happened to sort first.
  Future<List<RaceRankingEntry>> ranking({int limit = 20}) async {
    final rows = await _db.rawQuery(
      'SELECT winnerProviderId AS providerId, '
      'COUNT(*) AS wins, '
      'AVG(CASE WHEN winnerElapsedMs IS NOT NULL THEN winnerElapsedMs END) '
      'AS avgElapsed '
      'FROM dns_race_log '
      'WHERE success = 1 AND winnerProviderId IS NOT NULL '
      'GROUP BY winnerProviderId '
      'ORDER BY wins DESC, avgElapsed ASC '
      'LIMIT ?',
      [limit],
    );
    return [
      for (final row in rows)
        if ((row['providerId'] as String?)?.isNotEmpty == true)
          RaceRankingEntry(
            providerId: row['providerId']! as String,
            wins: (row['wins'] as num?)?.toInt() ?? 0,
            averageLatencyMs: ((row['avgElapsed'] as num?) ?? 0).round(),
          ),
    ];
  }

  Future<RaceLogSummary> summary() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS requests, '
      'SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) AS successes, '
      'SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) AS failures, '
      'AVG(elapsedMs) AS avgElapsed '
      'FROM dns_race_log',
    );
    if (rows.isEmpty) return const RaceLogSummary.empty();
    final row = rows.first;
    return RaceLogSummary(
      requests: (row['requests'] as num?)?.toInt() ?? 0,
      successes: (row['successes'] as num?)?.toInt() ?? 0,
      failures: (row['failures'] as num?)?.toInt() ?? 0,
      averageLatencyMs: ((row['avgElapsed'] as num?) ?? 0).round(),
    );
  }

  Future<List<RaceStrategyStatRow>> strategyStats({int? since}) async {
    final rows = await _db.rawQuery(
      'SELECT strategy, '
      'COUNT(*) AS requests, '
      'SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) AS successes, '
      'SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) AS failures, '
      'AVG(elapsedMs) AS avgElapsedMs, '
      'SUM(CASE WHEN fallbackUsed = 1 THEN 1 ELSE 0 END) AS fallbackUses, '
      'SUM(CASE WHEN fallbackSuccess = 1 THEN 1 ELSE 0 END) AS fallbackSuccesses, '
      'SUM(CASE WHEN selectedProviderId IS NOT NULL '
      'AND winnerProviderId = selectedProviderId AND success = 1 '
      'THEN 1 ELSE 0 END) AS primaryWins '
      'FROM dns_race_log'
      '${since == null ? '' : ' WHERE timestamp >= ?'} '
      'GROUP BY strategy '
      'ORDER BY strategy',
      [?since],
    );
    return [
      for (final row in rows)
        RaceStrategyStatRow(
          strategy: row['strategy'] as String? ?? '',
          requests: (row['requests'] as num?)?.toInt() ?? 0,
          successes: (row['successes'] as num?)?.toInt() ?? 0,
          failures: (row['failures'] as num?)?.toInt() ?? 0,
          averageElapsedMs: (row['avgElapsedMs'] as num?)?.toDouble() ?? 0,
          fallbackUses: (row['fallbackUses'] as num?)?.toInt() ?? 0,
          fallbackSuccesses: (row['fallbackSuccesses'] as num?)?.toInt() ?? 0,
          primaryWins: (row['primaryWins'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// `selectedSuccesses` requires no fallback, a win by the selected provider and success, so
  /// queries rescued by the fallback do not count.
  Future<List<RaceSmartSelectionRow>> smartSelectionStats({
    int? since,
    String strategy = 'smart_prediction',
  }) async {
    final rows = await _db.rawQuery(
      'SELECT selectedProviderId AS providerId, '
      'COUNT(*) AS selectedCount, '
      'SUM(CASE WHEN fallbackUsed = 0 AND winnerProviderId = selectedProviderId '
      'AND success = 1 THEN 1 ELSE 0 END) AS selectedSuccesses, '
      'AVG(selectedElapsedMs) AS avgSelectedElapsedMs '
      'FROM dns_race_log '
      'WHERE selectedProviderId IS NOT NULL AND strategy = ?'
      '${since == null ? '' : ' AND timestamp >= ?'} '
      'GROUP BY selectedProviderId '
      'ORDER BY selectedCount DESC',
      [strategy, ?since],
    );
    return [
      for (final row in rows)
        if ((row['providerId'] as String?)?.isNotEmpty == true)
          RaceSmartSelectionRow(
            providerId: row['providerId']! as String,
            selectedCount: (row['selectedCount'] as num?)?.toInt() ?? 0,
            selectedSuccesses: (row['selectedSuccesses'] as num?)?.toInt() ?? 0,
            averageElapsedMs:
                (row['avgSelectedElapsedMs'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  Future<int> clear() => _db.delete('dns_race_log');

  static RaceLogRecord _fromRow(Map<String, Object?> row) => RaceLogRecord(
    timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
    queryName: row['queryName'] as String? ?? '',
    strategy: row['strategy'] as String? ?? '',
    providerCount: (row['providerCount'] as num?)?.toInt() ?? 0,
    success: (row['success'] as num?)?.toInt() == 1,
    elapsedMs: (row['elapsedMs'] as num?)?.toInt() ?? 0,
    winnerProviderId: row['winnerProviderId'] as String?,
    winnerElapsedMs: (row['winnerElapsedMs'] as num?)?.toInt(),
    message: row['message'] as String?,
  );
}
