/// Automation state (A1 / A3 / A14): one database handle, one write revision, and the read/action
/// providers the editor, list and timeline share.
library;

import 'dart:async';

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/data/db/automation_repository.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_android/state/webhook_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// The main app database; `null` on a fresh install before the Dart schema exists.
final automationDatabaseProvider = FutureProvider<Database?>(
  (ref) => LegacyDatabase.open(LegacyDatabase.mainFile),
);

/// Bumped after every write so every read provider reloads.
class AutomationRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final automationRevisionProvider =
    NotifierProvider<AutomationRevisionNotifier, int>(
      AutomationRevisionNotifier.new,
    );

Future<AutomationRepository?> _repository(Ref ref) async {
  final db = await ref.read(automationDatabaseProvider.future);
  return db == null ? null : AutomationRepository(db);
}

/// Write actions shared by every automation screen.
class AutomationController {
  AutomationController(this._ref);

  final Ref _ref;

  void _bump() => _ref.read(automationRevisionProvider.notifier).bump();

  Future<void> saveRule(AutomationRule rule) async {
    await (await _repository(_ref))?.saveRule(rule);
    _bump();
  }

  Future<void> setRuleEnabled(String id, bool enabled) async {
    await (await _repository(_ref))?.setRuleEnabled(id, enabled);
    _bump();
  }

  Future<void> deleteRule(String id) async {
    await (await _repository(_ref))?.deleteRule(id);
    _bump();
  }

  Future<void> saveProfile(AutomationProfile profile) async {
    await (await _repository(_ref))?.saveProfile(profile);
    _bump();
  }

  Future<void> deleteProfile(String id) async {
    await (await _repository(_ref))?.deleteProfile(id);
    _bump();
  }

  Future<void> logEvent(AutomationEvent event) async {
    await (await _repository(_ref))?.logEvent(event);
    _bump();
    // A11: mirror the audit event to the user's webhook, fire-and-forget.
    unawaited(_ref.read(webhookActionsProvider).dispatch(event));
  }
}

final automationControllerProvider = Provider<AutomationController>(
  AutomationController.new,
);

final automationRulesProvider = FutureProvider<List<AutomationRule>>((ref) async {
  ref.watch(automationRevisionProvider);
  final repository = await _repository(ref);
  return repository == null ? const [] : repository.rules();
});

final automationRuleProvider = FutureProvider.family<AutomationRule?, String>((
  ref,
  id,
) async {
  ref.watch(automationRevisionProvider);
  final repository = await _repository(ref);
  if (repository == null) return null;
  return repository.rule(id);
});

final automationProfilesProvider = FutureProvider<List<AutomationProfile>>((
  ref,
) async {
  ref.watch(automationRevisionProvider);
  final repository = await _repository(ref);
  return repository == null ? const [] : repository.profiles();
});

final automationEventsProvider = FutureProvider<List<AutomationEvent>>((
  ref,
) async {
  ref.watch(automationRevisionProvider);
  final repository = await _repository(ref);
  return repository == null ? const [] : repository.events();
});
