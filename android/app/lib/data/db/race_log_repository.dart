/// Read/delete access to the legacy `dns_race_log` table; rows are written natively and provider
/// names are resolved in Dart, since native code only knows the ids. The SQL, averages and row
/// defaults live in `rust/diting-log-query-core`.
library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/rust_log_query_core.dart';

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

  factory RaceLogRecord.fromParsed(Map<String, Object?> row) => RaceLogRecord(
    timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
    queryName: row['queryName'] as String? ?? '',
    strategy: row['strategy'] as String? ?? '',
    providerCount: (row['providerCount'] as num?)?.toInt() ?? 0,
    success: row['success'] as bool? ?? false,
    elapsedMs: (row['elapsedMs'] as num?)?.toInt() ?? 0,
    winnerProviderId: row['winnerProviderId'] as String?,
    winnerElapsedMs: (row['winnerElapsedMs'] as num?)?.toInt(),
    message: row['message'] as String?,
  );

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

  /// The shape the race aggregates consume.
  Map<String, Object?> toKernel() => {
    'providerId': providerId,
    'wins': wins,
    'averageLatencyMs': averageLatencyMs,
  };
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

  Map<String, Object?> toKernel() => {
    'strategy': strategy,
    'requests': requests,
    'successes': successes,
    'failures': failures,
    'averageElapsedMs': averageElapsedMs,
    'fallbackUses': fallbackUses,
    'fallbackSuccesses': fallbackSuccesses,
    'primaryWins': primaryWins,
  };
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

  Map<String, Object?> toKernel() => {
    'providerId': providerId,
    'selectedCount': selectedCount,
    'selectedSuccesses': selectedSuccesses,
    'averageElapsedMs': averageElapsedMs,
  };
}

class RaceLogSummary {
  const RaceLogSummary({
    required this.requests,
    required this.successes,
    required this.failures,
    required this.averageLatencyMs,
  });

  factory RaceLogSummary.fromParsed(Map<String, Object?> row) => RaceLogSummary(
    requests: (row['requests'] as num?)?.toInt() ?? 0,
    successes: (row['successes'] as num?)?.toInt() ?? 0,
    failures: (row['failures'] as num?)?.toInt() ?? 0,
    averageLatencyMs: (row['averageLatencyMs'] as num?)?.toInt() ?? 0,
  );

  const RaceLogSummary.empty()
    : requests = 0,
      successes = 0,
      failures = 0,
      averageLatencyMs = 0;

  final int requests;
  final int successes;
  final int failures;
  final int averageLatencyMs;

  /// The shape the race aggregates consume.
  Map<String, Object?> toKernel() => {
    'requests': requests,
    'successes': successes,
    'failures': failures,
    'averageLatencyMs': averageLatencyMs,
  };
}

class RaceLogRepository {
  RaceLogRepository(this._db);

  final Database _db;

  Future<List<RaceLogRecord>> recent({int limit = 100}) async {
    final plan = RustLogQueryCore.instance.plan('race.recent', {'limit': limit});
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('race.row', rows))
        RaceLogRecord.fromParsed(row),
    ];
  }

  /// Wins are rows where this provider produced the winning response; failures are not pinned on
  /// the provider that happened to sort first.
  Future<List<RaceRankingEntry>> ranking({int limit = 20, int? since}) async {
    final plan = RustLogQueryCore.instance.plan('race.ranking', {
      'limit': limit,
      if (since != null) 'since': since,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('race.ranking', rows))
        if ((row['providerId'] as String?)?.isNotEmpty == true)
          RaceRankingEntry(
            providerId: row['providerId']! as String,
            wins: (row['wins'] as num?)?.toInt() ?? 0,
            averageLatencyMs: (row['averageLatencyMs'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  Future<RaceLogSummary> summary({int? since}) async {
    final plan = RustLogQueryCore.instance.plan('race.summary', {
      if (since != null) 'since': since,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    final parsed = RustLogQueryCore.instance.rows('race.summary', rows);
    return parsed.isEmpty
        ? const RaceLogSummary.empty()
        : RaceLogSummary.fromParsed(parsed.first);
  }

  Future<List<RaceStrategyStatRow>> strategyStats({int? since}) async {
    final plan = RustLogQueryCore.instance.plan('race.strategy', {
      if (since != null) 'since': since,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('race.strategy', rows))
        RaceStrategyStatRow(
          strategy: row['strategy'] as String? ?? '',
          requests: (row['requests'] as num?)?.toInt() ?? 0,
          successes: (row['successes'] as num?)?.toInt() ?? 0,
          failures: (row['failures'] as num?)?.toInt() ?? 0,
          averageElapsedMs:
              (row['averageElapsedMs'] as num?)?.toDouble() ?? 0,
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
    final plan = RustLogQueryCore.instance.plan('race.smart', {
      'strategy': strategy,
      if (since != null) 'since': since,
    });
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('race.smart', rows))
        if ((row['providerId'] as String?)?.isNotEmpty == true)
          RaceSmartSelectionRow(
            providerId: row['providerId']! as String,
            selectedCount: (row['selectedCount'] as num?)?.toInt() ?? 0,
            selectedSuccesses: (row['selectedSuccesses'] as num?)?.toInt() ?? 0,
            averageElapsedMs:
                (row['averageElapsedMs'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  Future<int> clear() => _db.delete('dns_race_log');
}
