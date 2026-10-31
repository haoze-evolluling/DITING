/// The single mutable copy of the three rule tables, so a page rebuild cannot drop edits made
/// elsewhere.
library;

import 'dart:async';

import 'package:diting/data/db/preset_whitelist.dart';
import 'package:diting/data/db/rule_bootstrap.dart';
import 'package:diting/data/db/rule_dataset_providers.dart';
import 'package:diting/data/db/rule_providers.dart';
import 'package:diting/data/db/rule_repository.dart';
import 'package:diting/data/mock_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Read-only check for preset whitelist rules, shared by the switch, row menu and delete action.
bool isRuleProtected(
  MockRule rule, {
  required RuleKind kind,
  required bool allowPresetEditable,
}) =>
    kind == RuleKind.allow &&
    rule.source == RuleSource.preset &&
    !allowPresetEditable;

/// The three rule tables keyed by kind; separate notifiers would duplicate the CRUD logic.
class RulesNotifier extends Notifier<Map<RuleKind, List<MockRule>>> {
  var _sequence = 0;

  RuleRepository? get _repo => ref.read(ruleRepositoryProvider);

  /// Recompiles the native rule tries of the active data set after a database write, mirroring the
  /// legacy app's cache refresh inside RuleOperationWorker. Cheap when nothing changed.
  void _refreshIndexes() {
    refreshRuleIndexesForCurrentMode(ref);
  }

  @override
  Map<RuleKind, List<MockRule>> build() {
    final initial = ref.watch(initialRulesProvider);
    // Only rules with an empty appScope belong here; app-scoped rules live on the app-rules page.
    return {
      for (final kind in RuleKind.values)
        kind: [
          for (final rule in initial[kind] ?? const <MockRule>[])
            if (rule.appScope == null) rule,
        ],
    };
  }

  List<MockRule> rulesOf(RuleKind kind) => state[kind] ?? const [];

  /// Toggles a rule; read-only rows are filtered by the caller.
  void toggle(RuleKind kind, String id, bool enabled) {
    _replace(kind, id, (rule) => _copy(rule, enabled: enabled));
    final repo = _repo;
    final dbId = int.tryParse(id);
    if (repo != null && dbId != null) {
      unawaited(repo.setEnabled(kind, dbId, enabled));
      _refreshIndexes();
    }
  }

  /// Adds a user rule; false when the pattern exists. Deduplication lives here because bulk import
  /// shares it.
  Future<bool> add(RuleKind kind, String pattern, {String? target}) async {
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

  /// Editing a whitelist preset rewrites its source to user-defined, so clearing presets cannot
  /// discard the edit.
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
    final matches = rulesOf(kind).where((rule) => rule.id == id);
    final current = matches.isEmpty ? null : matches.first;
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

  /// Clears user rules and returns how many were removed.
  Future<int> clearCustom(RuleKind kind) async {
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

  /// Resets default whitelist presets; user and subscription rows are kept.
  Future<int> resetPreset(RuleKind kind) async {
    final repo = _repo;
    if (repo != null && kind == RuleKind.allow) {
      final content = await rootBundle.loadString(
        'assets/https_passthrough.txt',
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

  /// Bulk import: appends deduplicated rows and returns how many were written.
  Future<int> importRules(
    RuleKind kind,
    List<String> patterns, {
    String? target,
  }) async {
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
      // One trie rebuild per batch, not one per row.
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

MockRule _copy(MockRule rule, {bool? enabled, bool? important}) => MockRule(
  id: rule.id,
  pattern: rule.pattern,
  kind: rule.kind,
  source: rule.source,
  enabled: enabled ?? rule.enabled,
  important: important ?? rule.important,
  group: rule.group,
  subscriptionName: rule.subscriptionName,
  target: rule.target,
);

final rulesProvider =
    NotifierProvider<RulesNotifier, Map<RuleKind, List<MockRule>>>(
      RulesNotifier.new,
    );

/// Read-only view of one rule kind; edits to other kinds do not rebuild it.
final rulesOfKindProvider = Provider.family<List<MockRule>, RuleKind>(
  (ref, kind) => ref.watch(rulesProvider)[kind] ?? const [],
);

/// One rule table narrowed by the source chip and the search box. A filter value rather than UI
/// state, so the tally and the list read the same snapshot and no page state feeds the stats.
@immutable
class RuleListFilter {
  const RuleListFilter({required this.kind, this.source, this.query = ''});

  final RuleKind kind;

  /// `null` shows every source.
  final RuleSourceFilter source;

  /// Already trimmed and lower-cased by the caller.
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

/// Rows the rule page shows for [filter]. Every row here is also matched by the tallies in
/// [ruleListTallyProvider], so the counter can never disagree with the list.
final filteredRulesProvider = Provider.family<List<MockRule>, RuleListFilter>(
  (ref, filter) => ref
      .watch(rulesOfKindProvider(filter.kind))
      .where((rule) {
        if (filter.source != null && rule.source != filter.source) {
          return false;
        }
        final query = filter.query;
        return query.isEmpty ||
            rule.pattern.toLowerCase().contains(query) ||
            (rule.target?.toLowerCase().contains(query) ?? false);
      })
      .toList(growable: false),
  // One entry per keystroke otherwise: the query string is part of the family key.
  isAutoDispose: true,
);

/// The three numbers above the rule list: table size, enabled rows and user-defined rows. Always
/// the whole table, not the filtered rows, matching the legacy screen.
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

  /// Rows left after the source chip and the query; what the "共 N 条" caption reports.
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

/// "Allow editing default whitelist" switch, off by default: relaxing the whitelist lets traffic
/// through.
class AllowPresetEditableNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final allowPresetEditableProvider =
    NotifierProvider<AllowPresetEditableNotifier, bool>(
      AllowPresetEditableNotifier.new,
    );

/// Rule-source filter; `null` means all sources.
typedef RuleSourceFilter = RuleSource?;

/// Parses one line into importable, duplicate or invalid; `#@#` lines are allow rules for the
/// whitelist page.
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

/// Parses pasted text; [existing] holds patterns already in the target table.
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

/// Keeps the rule list in step with the active data set. The startup fill covers the first mode;
/// every switch to another data set opens its database and reloads that data set's rows here, so
/// the page can never show another mode's rules while writing into the new one. Pages are published
/// as they arrive: a subscription-sized table never has to fit in memory at once.
final ruleSnapshotSyncProvider = Provider<void>((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  ref.listen<RuleRepository?>(ruleRepositoryProvider, (previous, next) {
    if (identical(previous, next)) return;
    final notifier = ref.read(initialRulesProvider.notifier);
    notifier.clear();
    if (next == null) return;
    unawaited(
      loadInitialRulesPaged(next, (kind, page) {
        if (disposed) return;
        notifier.append(kind, page);
      }),
    );
  });
});
