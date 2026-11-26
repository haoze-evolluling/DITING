library;

import 'package:diting_android/app/l10n/l10n.dart';

import 'package:diting_android/data/db/rule_dataset_providers.dart';
import 'package:diting_android/data/db/rule_providers.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppScopedRules {
  const AppScopedRules({
    required this.block,
    required this.allow,
    required this.fullBlock,
    this.available = true,
    this.error,
  });

  const AppScopedRules.unavailable([this.error])
    : block = const [],
      allow = const [],
      fullBlock = false,
      available = false;

  final List<MockRule> block;
  final List<MockRule> allow;

  final bool fullBlock;

  final bool available;

  final String? error;
}

final appScopedRulesProvider = FutureProvider.family<AppScopedRules, String>((
  ref,
  packageName,
) async {
  final repository = ref.watch(ruleRepositoryProvider);
  if (repository == null) {
    return AppScopedRules.unavailable(currentL10n.rulesDbUnavailable);
  }
  try {
    final rules = await repository.loadForApp(packageName);
    final fullBlock = await repository.hasFullBlock(packageName);
    return AppScopedRules(
      block: [
        for (final rule in rules)
          if (rule.kind == RuleKind.block) rule,
      ],
      allow: [
        for (final rule in rules)
          if (rule.kind == RuleKind.allow) rule,
      ],
      fullBlock: fullBlock,
    );
  } catch (error) {
    return AppScopedRules.unavailable(currentL10n.rulesReadFailed('$error'));
  }
});

class AppScopedRulesController {
  AppScopedRulesController(this._ref);

  final Ref _ref;

  RuleRepository? get _repository => _ref.read(ruleRepositoryProvider);

  void _afterWrite(String packageName) {
    refreshRuleIndexesForCurrentMode(_ref);
    _ref.invalidate(appScopedRulesProvider(packageName));
  }

  Future<bool> addRule(
    String packageName,
    RuleKind kind,
    String pattern, {
    bool important = false,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    final created = await repository.addForApp(
      kind,
      pattern,
      packageName,
      important: important,
    );
    if (created != null) {
      _afterWrite(packageName);
    }
    return created != null;
  }

  Future<void> toggle(String packageName, MockRule rule, bool enabled) async {
    final repository = _repository;
    final id = int.tryParse(rule.id);
    if (repository == null || id == null) return;
    await repository.setEnabled(rule.kind, id, enabled);
    _afterWrite(packageName);
  }

  Future<void> delete(String packageName, MockRule rule) async {
    final repository = _repository;
    final id = int.tryParse(rule.id);
    if (repository == null || id == null) return;
    await repository.delete(rule.kind, id);
    _afterWrite(packageName);
  }

  Future<bool> setFullBlock(String packageName, bool enabled) async {
    final repository = _repository;
    if (repository == null) return false;
    final next = await repository.setFullBlock(packageName, enabled);
    _afterWrite(packageName);
    return next;
  }
}

final appScopedRulesControllerProvider = Provider<AppScopedRulesController>(
  AppScopedRulesController.new,
);
