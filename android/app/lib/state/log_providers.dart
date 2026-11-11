/// Log data for the dashboard, read from the database of the active mode.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/dns_cache_repository.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_android/data/db/race_log_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// Normal and server modes share `diting_database`; express has its own file.
final activeLogDatabaseFileProvider = Provider<String>((ref) {
  final mode = ref.watch(workModeProvider);
  return mode == AppWorkMode.express
      ? LegacyDatabase.expressFile
      : LegacyDatabase.mainFile;
});

/// `null` on fresh installs, where the Dart layer has not created the file yet.
final activeLogDatabaseProvider = FutureProvider<Database?>(
  (ref) => LegacyDatabase.open(ref.watch(activeLogDatabaseFileProvider)),
);

/// All three dashboard views read the same file; "refresh" and "clear" bump the revision so one
/// action reloads them.
class DnsLogRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dnsLogRevisionProvider = NotifierProvider<DnsLogRevisionNotifier, int>(
  DnsLogRevisionNotifier.new,
);

Future<T> _viaDatabase<T>(
  Ref ref,
  Future<T> Function(Database db) build,
  T empty,
) async {
  final db = await ref.watch(activeLogDatabaseProvider.future);
  return db == null ? empty : build(db);
}

/// Latest rows from the active mode's database.
final dnsLogsProvider = FutureProvider<List<DnsLogRecord>>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  return _viaDatabase(
    ref,
    (db) => DnsLogRepository(db).recent(),
    const <DnsLogRecord>[],
  );
});

final dnsCacheProvider = FutureProvider<List<DnsCacheRecord>>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  return _viaDatabase(
    ref,
    (db) => DnsCacheRepository(db).entries(),
    const <DnsCacheRecord>[],
  );
});

/// Ranking rows with provider ids already resolved to display names.
final raceRankingProvider = FutureProvider<RaceRankingBoard>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final settings = ref.watch(legacySettingsProvider);
  final names = {
    for (final provider in [
      ...defaultDnsProviders(currentL10n),
      ...parseUserProviders(settings.userProvidersJson),
    ])
      provider.id: provider.name,
  };
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return const RaceRankingBoard.empty();
  final repository = RaceLogRepository(db);
  final entries = await repository.ranking();
  final summary = await repository.summary();
  final board = await deriveOffThread('race.board', {
    'summary': summary.toKernel(),
    'ranking': [for (final entry in entries) entry.toKernel()],
    'names': names,
  });
  final boardSummary = (board['summary'] as Map?) ?? const {};
  return RaceRankingBoard(
    summary: RaceSummary(
      requests: (boardSummary['requests'] as num?)?.toInt() ?? 0,
      failures: (boardSummary['failures'] as num?)?.toInt() ?? 0,
      averageLatencyMs:
          (boardSummary['averageLatencyMs'] as num?)?.toInt() ?? 0,
    ),
    entries: [
      for (final entry in board['entries'] as List? ?? const [])
        RaceRanking(
          provider: (entry as Map)['provider'] as String? ?? '',
          wins: (entry['wins'] as num?)?.toInt() ?? 0,
          averageLatencyMs:
              (entry['averageLatencyMs'] as num?)?.toInt() ?? 0,
        ),
    ],
  );
});

class RaceRankingBoard {
  const RaceRankingBoard({required this.summary, required this.entries});

  const RaceRankingBoard.empty()
    : summary = const RaceSummary(
        requests: 0,
        failures: 0,
        averageLatencyMs: 0,
      ),
      entries = const [];

  final RaceSummary summary;
  final List<RaceRanking> entries;
}

class RaceSummary {
  const RaceSummary({
    required this.requests,
    required this.failures,
    required this.averageLatencyMs,
  });

  final int requests;
  final int failures;
  final int averageLatencyMs;
}

class RaceRanking {
  const RaceRanking({
    required this.provider,
    required this.wins,
    required this.averageLatencyMs,
  });

  final String provider;
  final int wins;
  final int averageLatencyMs;
}
