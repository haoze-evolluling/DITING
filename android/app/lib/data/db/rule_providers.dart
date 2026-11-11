import 'dart:async';

import 'package:diting_shared/data/db/datasets.dart';
import 'package:diting_android/data/db/rule_bootstrap.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/app_version_provider.dart';
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

/// Rule tables of the active work mode's data set, read the first time anything actually needs
/// them (the rules pages, the batch editor, a rule edit) instead of at startup.
///
/// A subscription-sized table is ~10⁵ rows; materialising it in the UI isolate right after
/// `runApp` cost a long stall and 20–35 MB for users who never open those pages, and the four
/// picker/batch pages that mutate rules already read this provider, so deferring loses nothing.
/// The fill stays paged, so rows appear while the rest of a big table is still being read.
class InitialRulesNotifier extends Notifier<Map<RuleKind, List<MockRule>>> {
  /// Bumped whenever the fill restarts, so pages from a superseded read are dropped.
  int _generation = 0;

  /// Completes when the fill for [_generation] has finished, so a mutation cannot append to a
  /// half-filled list.
  Future<void> _loaded = Future<void>.value();

  @override
  Map<RuleKind, List<MockRule>> build() {
    // Re-runs when the data set changes (mode switch opens another database), which is also what
    // makes the previous mode's rows disappear immediately.
    final repository = ref.watch(ruleRepositoryProvider);
    final generation = ++_generation;
    if (repository == null) {
      _loaded = Future<void>.value();
      return _emptyRules();
    }
    _loaded = loadInitialRulesPaged(repository, (kind, page) {
      if (generation != _generation) return;
      append(kind, page);
    });
    return _emptyRules();
  }

  /// Awaits the in-flight fill; a no-op once it has finished.
  Future<void> ensureLoaded() => _loaded;

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
