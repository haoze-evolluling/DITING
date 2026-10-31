import 'dart:async';

import 'package:diting/data/db/datasets.dart';
import 'package:diting/data/db/rule_bootstrap.dart';
import 'package:diting/data/db/rule_repository.dart';
import 'package:diting/data/mock_data.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/state/app_version_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Handle opened before the first frame by `main()` for the startup data set. Reusing it keeps the
/// normal mode on one connection; tests and hosts without SQLite leave it null.
final startupRuleRepositoryProvider = Provider<RuleRepository?>((ref) => null);

/// Rule handles opened in this process, keyed by database file. Each data set is opened (and its
/// whitelist seeded) at most once; switching back reuses the handle.
class RuleRepositoriesNotifier extends Notifier<Map<String, RuleRepository>> {
  final _opening = <String>{};
  var _disposed = false;

  @override
  Map<String, RuleRepository> build() {
    ref.onDispose(() => _disposed = true);
    final startup = ref.read(startupRuleRepositoryProvider);
    final file = startup?.sourceFile;
    if (startup == null || file == null) return const {};
    return {file: startup};
  }

  Future<void> ensure(DataSet dataSet) async {
    if (state.containsKey(dataSet.ruleDatabase) ||
        !_opening.add(dataSet.ruleDatabase)) {
      return;
    }
    try {
      final bootstrap = await bootstrapRules(
        dataSet,
        LegacySettings(
          ref.read(legacyPrefsStoreProvider),
          dnsContainer: dataSet.prefsContainer,
        ),
        versionCode: ref.read(appVersionProvider).code,
      );
      final repository = bootstrap.repository;
      if (repository == null || _disposed) return;
      state = {...state, dataSet.ruleDatabase: repository};
    } finally {
      _opening.remove(dataSet.ruleDatabase);
    }
  }
}

final ruleRepositoriesProvider =
    NotifierProvider<RuleRepositoriesNotifier, Map<String, RuleRepository>>(
      RuleRepositoriesNotifier.new,
    );

/// Rule tables and subscriptions of the active work mode's data set; null while that database is
/// opening (the first switch to a mode pays one open, later switches are immediate).
final ruleRepositoryProvider = Provider<RuleRepository?>((ref) {
  final dataSet = ref.watch(activeDataSetProvider);
  final repositories = ref.watch(ruleRepositoriesProvider);
  final repository = repositories[dataSet.ruleDatabase];
  if (repository == null) {
    unawaited(ref.read(ruleRepositoriesProvider.notifier).ensure(dataSet));
  }
  return repository;
});

/// Filled once the UI is up (the full-table load must not block the first frame) and refilled by
/// `ruleSnapshotSyncProvider` when the data set changes. The fill is paged, so the rules page shows
/// rows while the rest of a subscription-sized table is still being read.
class InitialRulesNotifier extends Notifier<Map<RuleKind, List<MockRule>>> {
  @override
  Map<RuleKind, List<MockRule>> build() => _emptyRules();

  /// Appends one page of the paged load. Pages arrive in `id DESC` order, so the list keeps the
  /// same order a full load produced.
  void append(RuleKind kind, List<MockRule> page) {
    if (page.isEmpty) return;
    state = {
      ...state,
      kind: [...?state[kind], ...page],
    };
  }

  /// Empties the snapshot while a newly selected data set's database opens, so the page cannot
  /// keep showing another mode's rows.
  void clear() => state = _emptyRules();
}

final initialRulesProvider =
    NotifierProvider<InitialRulesNotifier, Map<RuleKind, List<MockRule>>>(
      InitialRulesNotifier.new,
    );

Map<RuleKind, List<MockRule>> _emptyRules() => {
  for (final kind in RuleKind.values) kind: const [],
};
