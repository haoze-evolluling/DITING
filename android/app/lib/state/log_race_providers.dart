/// Race log data (table `dns_race_log`); shares `activeLogDatabaseProvider` and
/// `dnsLogRevisionProvider` only.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/race_log_repository.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/state/log_dashboard_providers.dart' show LogStatsRange;
import 'package:diting_android/state/log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// Race window currently selected on the page.
class RaceStatsRangeNotifier extends Notifier<LogStatsRange> {
  @override
  LogStatsRange build() => LogStatsRange.today;

  void select(LogStatsRange range) {
    if (state == range) return;
    state = range;
  }
}

final raceStatsRangeProvider =
    NotifierProvider<RaceStatsRangeNotifier, LogStatsRange>(
      RaceStatsRangeNotifier.new,
    );

/// Maps a stored strategy to its display name; old aliases (`race`, `prediction`) are read, so no
/// row shows a raw value.
String raceStrategyLabel(String strategy) => switch (strategy) {
  'parallel_race' || 'race' || 'brute_force_parallel' => currentL10n.logRaceFastest,
  'smart_prediction' || 'prediction' => currentL10n.logRaceSmart,
  'primary_backup' => currentL10n.logRaceSequential,
  'single' => currentL10n.logRaceSingle,
  _ => strategy,
};

class RaceStrategyDisplay {
  const RaceStrategyDisplay({
    required this.strategy,
    required this.label,
    required this.requests,
    required this.successes,
    required this.failures,
    required this.averageElapsedMs,
    required this.fallbackUses,
    required this.primaryWins,
  });

  final String strategy;

  /// Display name; unknown strategies fall back to the stored value.
  final String label;
  final int requests;
  final int successes;
  final int failures;
  final double averageElapsedMs;

  /// Fallback uses (another provider was tried) and how many won.
  final int fallbackUses;
  final int primaryWins;

  double get successRate => requests == 0 ? 0 : successes / requests;

  /// Primary win rate; only meaningful for smart selection, 0 otherwise.
  double get primaryWinRate => requests == 0 ? 0 : primaryWins / requests;
}

class RaceSmartSelectionDisplay {
  const RaceSmartSelectionDisplay({
    required this.name,
    required this.selectedCount,
    required this.selectedSuccesses,
    required this.averageElapsedMs,
  });

  final String name;
  final int selectedCount;
  final int selectedSuccesses;
  final double averageElapsedMs;

  double get selectedSuccessRate =>
      selectedCount == 0 ? 0 : selectedSuccesses / selectedCount;
}

class RaceStatsSnapshot {
  const RaceStatsSnapshot({
    required this.summary,
    required this.entries,
    this.strategyStats = const [],
    this.smartSelections = const [],
  });

  const RaceStatsSnapshot.empty()
    : summary = const RaceLogSummary.empty(),
      entries = const [],
      strategyStats = const [],
      smartSelections = const [];

  final RaceLogSummary summary;

  /// Provider win ranking with ids resolved to display names.
  final List<({String name, int wins, int averageLatencyMs})> entries;

  final List<RaceStrategyDisplay> strategyStats;

  /// Smart-selection primaries with names resolved.
  final List<RaceSmartSelectionDisplay> smartSelections;
}

/// Aggregates the selected window, unlike `raceRankingProvider`, which would make the range
/// selector do nothing.
final raceStatsProvider = FutureProvider<RaceStatsSnapshot>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final range = ref.watch(raceStatsRangeProvider);
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const RaceStatsSnapshot.empty();
  final since = range.startOf(DateTime.now())?.millisecondsSinceEpoch;

  final summaryRows = await db.rawQuery(
    'SELECT COUNT(*) AS requests, '
    'COALESCE(SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END), 0) AS successes, '
    'COALESCE(SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END), 0) AS failures, '
    'AVG(elapsedMs) AS avgElapsed FROM dns_race_log'
    '${since == null ? '' : ' WHERE timestamp >= ?'}',
    [?since],
  );
  final summaryRow = summaryRows.isEmpty ? null : summaryRows.first;
  final summary = RaceLogSummary(
    requests: (summaryRow?['requests'] as num?)?.toInt() ?? 0,
    successes: (summaryRow?['successes'] as num?)?.toInt() ?? 0,
    failures: (summaryRow?['failures'] as num?)?.toInt() ?? 0,
    averageLatencyMs: ((summaryRow?['avgElapsed'] as num?) ?? 0).round(),
  );

  final rankingRows = await db.rawQuery(
    'SELECT winnerProviderId AS providerId, COUNT(*) AS wins, '
    'AVG(CASE WHEN winnerElapsedMs IS NOT NULL THEN winnerElapsedMs END) '
    'AS avgElapsed FROM dns_race_log '
    'WHERE success = 1 AND winnerProviderId IS NOT NULL'
    '${since == null ? '' : ' AND timestamp >= ?'} '
    'GROUP BY winnerProviderId ORDER BY wins DESC, avgElapsed ASC LIMIT 20',
    [?since],
  );

  // Resolve names from the same catalog as `raceRankingProvider`, or one provider shows two names
  // across pages.
  final settings = ref.watch(legacySettingsProvider);
  final names = {
    for (final provider in [
      ...defaultDnsProviders(currentL10n),
      ...parseUserProviders(settings.userProvidersJson),
    ])
      provider.id: provider.name,
  };

  // Older databases lack `fallbackUsed`/`selectedProviderId`; leave those two groups empty, keep
  // the rest working.
  final repository = RaceLogRepository(db);
  var strategyRows = const <RaceStrategyStatRow>[];
  var smartRows = const <RaceSmartSelectionRow>[];
  try {
    strategyRows = await repository.strategyStats(since: since);
    smartRows = await repository.smartSelectionStats(since: since);
  } on DatabaseException catch (error) {
    if (!error.toString().contains('no such column')) rethrow;
  }

  return RaceStatsSnapshot(
    summary: summary,
    entries: [
      for (final row in rankingRows)
        if ((row['providerId'] as String?)?.isNotEmpty == true)
          (
            name: names[row['providerId']] ?? row['providerId']! as String,
            wins: (row['wins'] as num?)?.toInt() ?? 0,
            averageLatencyMs: ((row['avgElapsed'] as num?) ?? 0).round(),
          ),
    ],
    strategyStats: [
      for (final row in strategyRows)
        RaceStrategyDisplay(
          strategy: row.strategy,
          label: raceStrategyLabel(row.strategy),
          requests: row.requests,
          successes: row.successes,
          failures: row.failures,
          averageElapsedMs: row.averageElapsedMs,
          fallbackUses: row.fallbackUses,
          primaryWins: row.primaryWins,
        ),
    ],
    smartSelections: [
      for (final row in smartRows)
        RaceSmartSelectionDisplay(
          name: names[row.providerId] ?? row.providerId,
          selectedCount: row.selectedCount,
          selectedSuccesses: row.selectedSuccesses,
          averageElapsedMs: row.averageElapsedMs,
        ),
    ],
  );
});
