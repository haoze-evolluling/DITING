library;

import 'dart:async';

import 'package:diting_android/data/db/preset_whitelist.dart';
import 'package:diting_android/data/db/rule_dataset_providers.dart';
import 'package:diting_android/data/db/rule_providers.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/rules/rule_search_index.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool isRuleProtected(
  MockRule rule, {
  required RuleKind kind,
  required bool allowPresetEditable,
}) =>
    kind == RuleKind.allow &&
    rule.source == RuleSource.preset &&
    !allowPresetEditable;

class RulesNotifier extends Notifier<Map<RuleKind, List<MockRule>>> {
  var _sequence = 0;

  RuleRepository? get _repo => ref.read(ruleRepositoryProvider);

  Future<void> _awaitSnapshot() =>
      ref.read(initialRulesProvider.notifier).ensureLoaded();

  /// 其它页面读取规则时调用，确保被规则列表页暂停的加载继续执行。
  Future<void> ensureLoaded() => _awaitSnapshot();

  void _refreshIndexes() {
    refreshRuleIndexesForCurrentMode(ref);
  }

  @override
  Map<RuleKind, List<MockRule>> build() {
    final initial = ref.watch(initialRulesProvider);
    return {
      for (final kind in RuleKind.values)
        kind: [
          for (final rule in initial[kind] ?? const <MockRule>[])
            if (rule.appScope == null) rule,
        ],
    };
  }

  List<MockRule> rulesOf(RuleKind kind) => state[kind] ?? const [];

  void toggle(RuleKind kind, String id, bool enabled) {
    _replace(kind, id, (rule) => _copy(rule, enabled: enabled));
    final repo = _repo;
    final dbId = int.tryParse(id);
    if (repo != null && dbId != null) {
      unawaited(repo.setEnabled(kind, dbId, enabled));
      _refreshIndexes();
    }
  }

  Future<bool> add(RuleKind kind, String pattern, {String? target}) async {
    await _awaitSnapshot();
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (rulesOf(kind).any((rule) => rule.pattern == trimmed)) {
      return false;
    }
    final repo = _repo;
    if (repo != null) {
      final created = await repo.add(kind, trimmed, target: target);
      state = {
        ...state,
        kind: [created, ...rulesOf(kind)],
      };
      _refreshIndexes();
      return true;
    }
    state = {
      ...state,
      kind: [
        MockRule(
          id: '${kind.name}-user-${_sequence++}',
          pattern: trimmed,
          kind: kind,
          source: RuleSource.user,
          target: target,
        ),
        ...rulesOf(kind),
      ],
    };
    return true;
  }

  Future<void> edit(
    RuleKind kind,
    String id,
    String pattern, {
    String? target,
  }) async {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final current = rulesOf(kind).where((rule) => rule.id == id).firstOrNull;
    final repo = _repo;
    final dbId = int.tryParse(id);
    if (repo != null && dbId != null) {
      await repo.update(
        kind,
        dbId,
        trimmed,
        target: target,
        promotePreset: current?.source == RuleSource.preset,
      );
      _refreshIndexes();
    }
    _replace(
      kind,
      id,
      (rule) => MockRule(
        id: rule.id,
        pattern: trimmed,
        kind: rule.kind,
        source: rule.source == RuleSource.preset
            ? RuleSource.user
            : rule.source,
        enabled: rule.enabled,
        important: rule.important,
        group: rule.group,
        subscriptionName: rule.subscriptionName,
        target: target ?? rule.target,
      ),
    );
  }

  Future<void> remove(RuleKind kind, String id) async {
    await _awaitSnapshot();
    final repo = _repo;
    final dbId = int.tryParse(id);
    if (repo != null && dbId != null) {
      await repo.delete(kind, dbId);
      _refreshIndexes();
    }
    state = {
      ...state,
      kind: [
        for (final rule in rulesOf(kind))
          if (rule.id != id) rule,
      ],
    };
  }

  Future<int> clearCustom(RuleKind kind) async {
    await _awaitSnapshot();
    final repo = _repo;
    final removed = repo == null
        ? rulesOf(kind).where((rule) => rule.source == RuleSource.user).length
        : await repo.clearUser(kind);
    if (repo != null && removed > 0) {
      _refreshIndexes();
    }
    state = {
      ...state,
      kind: [
        for (final rule in rulesOf(kind))
          if (rule.source != RuleSource.user) rule,
      ],
    };
    return removed;
  }

  Future<int> resetPreset(RuleKind kind) async {
    await _awaitSnapshot();
    final repo = _repo;
    if (repo != null && kind == RuleKind.allow) {
      final content = await rootBundle.loadString(
        'packages/diting_shared/assets/https_passthrough.txt',
      );
      final entries = parsePresetWhitelist(content);
      if (entries.isEmpty) {
        return 0;
      }
      final count = await repo.resetPresetWhitelist(entries);
      _refreshIndexes();
      state = {...state, kind: await repo.loadKind(kind)};
      return count;
    }
    final initial = {
      for (final rule in mockRulesOf(kind))
        if (rule.source == RuleSource.preset) rule.id: rule,
    };
    final kept = [
      for (final rule in rulesOf(kind))
        if (rule.source != RuleSource.preset) rule,
    ];
    state = {
      ...state,
      kind: [...kept, ...initial.values],
    };
    return initial.length;
  }

  Future<int> importRules(
    RuleKind kind,
    List<String> patterns, {
    String? target,
  }) async {
    await _awaitSnapshot();
    final existing = {for (final rule in rulesOf(kind)) rule.pattern};
    final repo = _repo;
    final added = <MockRule>[];
    for (final pattern in patterns) {
      final trimmed = pattern.trim();
      if (trimmed.isEmpty || !existing.add(trimmed)) {
        continue;
      }
      if (repo != null) {
        added.add(await repo.add(kind, trimmed, target: target));
      } else {
        added.add(
          MockRule(
            id: '${kind.name}-user-${_sequence++}',
            pattern: trimmed,
            kind: kind,
            source: RuleSource.user,
            target: target,
          ),
        );
      }
    }
    if (added.isEmpty) {
      return 0;
    }
    if (repo != null) {
      _refreshIndexes();
    }
    state = {
      ...state,
      kind: [...added.reversed, ...rulesOf(kind)],
    };
    return added.length;
  }

  void _replace(RuleKind kind, String id, MockRule Function(MockRule) update) {
    state = {
      ...state,
      kind: [
        for (final rule in rulesOf(kind))
          if (rule.id == id) update(rule) else rule,
      ],
    };
  }
}

MockRule _copy(MockRule rule, {bool? enabled}) => MockRule(
  id: rule.id,
  pattern: rule.pattern,
  kind: rule.kind,
  source: rule.source,
  enabled: enabled ?? rule.enabled,
  important: rule.important,
  group: rule.group,
  subscriptionName: rule.subscriptionName,
  target: rule.target,
);

final rulesProvider =
    NotifierProvider<RulesNotifier, Map<RuleKind, List<MockRule>>>(
      RulesNotifier.new,
    );

final rulesOfKindProvider = Provider.family<List<MockRule>, RuleKind>(
  (ref, kind) => ref.watch(rulesProvider)[kind] ?? const [],
);

@immutable
class RuleListFilter {
  const RuleListFilter({required this.kind, this.source, this.query = ''});

  final RuleKind kind;

  final RuleSourceFilter source;

  final String query;

  @override
  bool operator ==(Object other) =>
      other is RuleListFilter &&
      other.kind == kind &&
      other.source == source &&
      other.query == query;

  @override
  int get hashCode => Object.hash(kind, source, query);
}

final ruleSearchIndexProvider = Provider.family<RuleSearchIndex, RuleKind>((
  ref,
  kind,
) {
  final rules = ref.watch(rulesOfKindProvider(kind));
  final index = RuleSearchIndex(
    () => [
      for (final rule in rules) (pattern: rule.pattern, target: rule.target),
    ],
  );
  ref.onDispose(index.dispose);
  return index;
});

final filteredRulesProvider = Provider.family<List<MockRule>, RuleListFilter>(
  (ref, filter) {
    final rules = ref.watch(rulesOfKindProvider(filter.kind));
    final source = filter.source;
    final query = filter.query;
    if (query.isEmpty) {
      return [
        for (final rule in rules)
          if (source == null || rule.source == source) rule,
      ];
    }
    final hits = ref.watch(ruleSearchIndexProvider(filter.kind)).match(query);
    return [
      for (final index in hits)
        if (source == null || rules[index].source == source) rules[index],
    ];
  },
  isAutoDispose: true,
);

@immutable
class RuleListTally {
  const RuleListTally({
    required this.total,
    required this.enabled,
    required this.custom,
    required this.matched,
    required this.matchedEnabled,
  });

  final int total;
  final int enabled;
  final int custom;

  final int matched;
  final int matchedEnabled;

  @override
  bool operator ==(Object other) =>
      other is RuleListTally &&
      other.total == total &&
      other.enabled == enabled &&
      other.custom == custom &&
      other.matched == matched &&
      other.matchedEnabled == matchedEnabled;

  @override
  int get hashCode =>
      Object.hash(total, enabled, custom, matched, matchedEnabled);
}

final ruleListTallyProvider = Provider.family<RuleListTally, RuleListFilter>((
  ref,
  filter,
) {
  var total = 0;
  var enabled = 0;
  var custom = 0;
  for (final rule in ref.watch(rulesOfKindProvider(filter.kind))) {
    total++;
    if (rule.enabled) {
      enabled++;
    }
    if (rule.source == RuleSource.user) {
      custom++;
    }
  }
  var matchedEnabled = 0;
  final matched = ref.watch(filteredRulesProvider(filter));
  for (final rule in matched) {
    if (rule.enabled) {
      matchedEnabled++;
    }
  }
  return RuleListTally(
    total: total,
    enabled: enabled,
    custom: custom,
    matched: matched.length,
    matchedEnabled: matchedEnabled,
  );
}, isAutoDispose: true);

class AllowPresetEditableNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final allowPresetEditableProvider =
    NotifierProvider<AllowPresetEditableNotifier, bool>(
      AllowPresetEditableNotifier.new,
    );

typedef RuleSourceFilter = RuleSource?;

class RuleLineParseResult {
  const RuleLineParseResult({
    required this.accepted,
    required this.duplicated,
    required this.rejected,
  });

  final List<String> accepted;
  final List<String> duplicated;
  final List<String> rejected;
}

RuleLineParseResult parseRuleLines(
  String text, {
  Set<String> existing = const {},
}) {
  final accepted = <String>[];
  final duplicated = <String>[];
  final rejected = <String>[];
  final seen = {...existing};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.contains('#@#')) {
      rejected.add(line);
      continue;
    }
    if (!seen.add(line)) {
      duplicated.add(line);
      continue;
    }
    accepted.add(line);
  }
  return RuleLineParseResult(
    accepted: accepted,
    duplicated: duplicated,
    rejected: rejected,
  );
}
