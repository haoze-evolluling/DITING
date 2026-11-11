/// Race log data (table `dns_race_log`); shares `activeLogDatabaseProvider` and
/// `dnsLogRevisionProvider` only.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/race_log_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
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
  final repository = RaceLogRepository(db);

  final summary = await repository.summary(since: since);
  final ranking = await repository.ranking(since: since);

  // Older databases lack `fallbackUsed`/`selectedProviderId`; leave those two groups empty, keep
  // the rest working.
  var strategyRows = const <RaceStrategyStatRow>[];
  var smartRows = const <RaceSmartSelectionRow>[];
  try {
    strategyRows = await repository.strategyStats(since: since);
    smartRows = await repository.smartSelectionStats(since: since);
  } on DatabaseException catch (error) {
    if (!error.toString().contains('no such column')) rethrow;
  }

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

  final answer = RustLogQueryCore.instance.derive('race.stats', {
    'summary': summary.toKernel(),
    'ranking': [for (final row in ranking) row.toKernel()],
    'strategy': [for (final row in strategyRows) row.toKernel()],
    'smart': [for (final row in smartRows) row.toKernel()],
    'names': names,
  });

  return RaceStatsSnapshot(
    summary: RaceLogSummary.fromParsed(
      (answer['summary'] as Map).cast<String, Object?>(),
    ),
    entries: [
      for (final row in answer['entries'] as List? ?? const [])
        (
          name: (row as Map)['name'] as String? ?? '',
          wins: (row['wins'] as num?)?.toInt() ?? 0,
          averageLatencyMs:
              (row['averageLatencyMs'] as num?)?.toInt() ?? 0,
        ),
    ],
    strategyStats: [
      for (final row in answer['strategyStats'] as List? ?? const [])
        RaceStrategyDisplay(
          strategy: (row as Map)['strategy'] as String? ?? '',
          label: raceStrategyLabel(row['strategy'] as String? ?? ''),
          requests: (row['requests'] as num?)?.toInt() ?? 0,
          successes: (row['successes'] as num?)?.toInt() ?? 0,
          failures: (row['failures'] as num?)?.toInt() ?? 0,
          averageElapsedMs:
              (row['averageElapsedMs'] as num?)?.toDouble() ?? 0,
          fallbackUses: (row['fallbackUses'] as num?)?.toInt() ?? 0,
          primaryWins: (row['primaryWins'] as num?)?.toInt() ?? 0,
        ),
    ],
    smartSelections: [
      for (final row in answer['smartSelections'] as List? ?? const [])
        RaceSmartSelectionDisplay(
          name: (row as Map)['name'] as String? ?? '',
          selectedCount: (row['selectedCount'] as num?)?.toInt() ?? 0,
          selectedSuccesses: (row['selectedSuccesses'] as num?)?.toInt() ?? 0,
          averageElapsedMs:
              (row['averageElapsedMs'] as num?)?.toDouble() ?? 0,
        ),
    ],
  );
});
