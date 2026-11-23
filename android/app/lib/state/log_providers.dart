library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/dns_cache_repository.dart';
import 'package:diting_shared/data/db/app_database.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

final activeLogDatabaseFileProvider = Provider<String>((ref) {
  return ref.watch(activeDataSetProvider).logsDatabase;
});

final activeLogDatabaseProvider = FutureProvider<Database?>(
  (ref) => AppDatabase.open(ref.watch(activeLogDatabaseFileProvider)),
);

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

Map<String, String> providerDisplayNames(LegacySettings settings) => {
  for (final provider in [
    ...defaultDnsProviders(currentL10n),
    ...parseUserProviders(settings.userProvidersJson),
  ])
    provider.id: provider.name,
};


final dnsCacheProvider = FutureProvider<List<DnsCacheRecord>>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  return _viaDatabase(
    ref,
    (db) => DnsCacheRepository(db).entries(),
    const <DnsCacheRecord>[],
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
