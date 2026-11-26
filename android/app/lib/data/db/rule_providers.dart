import 'dart:async';

import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/db/rule_bootstrap.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/app_version_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final startupRuleRepositoryProvider = Provider<RuleRepository?>((ref) => null);

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
    final databaseFile = dataSet.ruleDatabase;
    if (state.containsKey(databaseFile) || !_opening.add(databaseFile)) {
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
      state = {...state, databaseFile: repository};
    } finally {
      _opening.remove(databaseFile);
    }
  }
}

final ruleRepositoriesProvider =
    NotifierProvider<RuleRepositoriesNotifier, Map<String, RuleRepository>>(
      RuleRepositoriesNotifier.new,
    );

final ruleRepositoryProvider = Provider<RuleRepository?>((ref) {
  final dataSet = ref.watch(activeDataSetProvider);
  final databaseFile = dataSet.ruleDatabase;
  final repositories = ref.watch(ruleRepositoriesProvider);
  final repository = repositories[databaseFile];
  if (repository == null) {
    unawaited(ref.read(ruleRepositoriesProvider.notifier).ensure(dataSet));
  }
  return repository;
});

class InitialRulesNotifier extends Notifier<Map<RuleKind, List<MockRule>>> {
  int _generation = 0;

  Future<void> _loaded = Future<void>.value();

  bool _paused = false;

  final List<Completer<void>> _resumeWaiters = [];

  @override
  Map<RuleKind, List<MockRule>> build() {
    final repository = ref.watch(ruleRepositoryProvider);
    final generation = ++_generation;
    if (repository == null) {
      _loaded = Future<void>.value();
      return _emptyRules();
    }
    _loaded = loadInitialRulesPaged(
      repository,
      (kind, page) {
        if (generation != _generation) return;
        append(kind, page);
      },
      beforePage: _whenResumed,
    );
    return _emptyRules();
  }

  /// 暂停分页加载。规则列表页不可见时调用，避免在其它页面继续做
  /// 全量计数、筛选和搜索索引计算。
  void pause() => _paused = true;

  /// 恢复分页加载；未处于暂停状态时为空操作。
  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_resumeWaiters.isEmpty) return;
    final waiters = List<Completer<void>>.of(_resumeWaiters);
    _resumeWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> _whenResumed() {
    if (!_paused) return Future<void>.value();
    final waiter = Completer<void>();
    _resumeWaiters.add(waiter);
    return waiter.future;
  }

  Future<void> ensureLoaded() {
    resume();
    return _loaded;
  }

  void append(RuleKind kind, List<MockRule> page) {
    if (page.isEmpty) return;
    state = {
      ...state,
      kind: [...?state[kind], ...page],
    };
  }

  void clear() => state = _emptyRules();
}

final initialRulesProvider =
    NotifierProvider<InitialRulesNotifier, Map<RuleKind, List<MockRule>>>(
      InitialRulesNotifier.new,
    );

Map<RuleKind, List<MockRule>> _emptyRules() => {
  for (final kind in RuleKind.values) kind: const [],
};
