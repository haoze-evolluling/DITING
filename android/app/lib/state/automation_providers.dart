library;

import 'dart:async';

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/data/db/automation_repository.dart';
import 'package:diting_android/data/native/automation_bridge.dart';
import 'package:diting_android/data/db/app_database.dart';
import 'package:diting_android/data/db/storage_contract.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

final automationDatabaseFileProvider = Provider<String>((ref) {
  return StorageContract.globalDatabase;
});

final automationBridgeProvider = Provider<AutomationBridge>(
  (ref) => AutomationBridge(),
);

class ExternalAutomationNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(legacySettingsProvider).externalAutomationEnabled;

  void setEnabled(bool value) {
    ref.read(legacySettingsProvider).setExternalAutomationEnabled(value);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

final externalAutomationEnabledProvider =
    NotifierProvider<ExternalAutomationNotifier, bool>(
      ExternalAutomationNotifier.new,
    );

final automationDatabaseProvider = FutureProvider<Database?>(
  (ref) => AppDatabase.open(ref.watch(automationDatabaseFileProvider)),
);

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

class AutomationController {
  AutomationController(this._ref);

  final Ref _ref;

  void _bump() => _ref.read(automationRevisionProvider.notifier).bump();

  Future<void> saveRule(AutomationRule rule) async {
    await (await _repository(_ref))?.saveRule(rule);
    _bump();
    await _ref.read(automationBridgeProvider).reschedule();
  }

  Future<void> setRuleEnabled(String id, bool enabled) async {
    await (await _repository(_ref))?.setRuleEnabled(id, enabled);
    _bump();
    await _ref.read(automationBridgeProvider).reschedule();
  }

  Future<void> deleteRule(String id) async {
    await (await _repository(_ref))?.deleteRule(id);
    _bump();
    await _ref.read(automationBridgeProvider).reschedule();
  }

  Future<int> runNow({String eventType = 'manual'}) async {
    final count = await _ref
        .read(automationBridgeProvider)
        .runNow(eventType: eventType);
    _bump();
    return count;
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
  }
}

final automationControllerProvider = Provider<AutomationController>(
  AutomationController.new,
);

final automationRulesProvider = FutureProvider<List<AutomationRule>>((
  ref,
) async {
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
