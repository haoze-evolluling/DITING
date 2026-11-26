library;

import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/auto_update_schedule.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:diting_android/state/auto_update_schedule.dart';

class AutoUpdateSettings {
  const AutoUpdateSettings({
    required this.enabled,
    required this.intervalHours,
    this.schedule = AutoUpdateSchedule.interval,
    this.timeMinutes = LegacySettings.defaultSubscriptionAutoUpdateTimeMinutes,
    this.sinceMs = 0,
  });

  final bool enabled;
  final int intervalHours;
  final AutoUpdateSchedule schedule;

  final int timeMinutes;
  final int sinceMs;

  bool get isCustom =>
      !LegacySettings.subscriptionAutoUpdatePresetHours.contains(intervalHours);

  AutoUpdatePlan get plan => AutoUpdatePlan(
    schedule: schedule,
    intervalHours: intervalHours,
    timeMinutes: timeMinutes,
    sinceMs: sinceMs,
  );
}

final autoUpdateSettingsProvider = Provider<AutoUpdateSettings>((ref) {
  final settings = ref.watch(legacySettingsProvider);
  return AutoUpdateSettings(
    enabled: settings.subscriptionAutoUpdateEnabled,
    intervalHours: settings.subscriptionAutoUpdateIntervalHours,
    schedule: AutoUpdateSchedule.fromStorage(
      settings.subscriptionAutoUpdateScheduleRaw,
    ),
    timeMinutes: settings.subscriptionAutoUpdateTimeMinutes,
    sinceMs: settings.subscriptionAutoUpdateSinceMs,
  );
});

class AutoUpdateActions {
  AutoUpdateActions(this._ref);

  final Ref _ref;

  void _bump() => _ref.read(legacySettingsRevisionProvider.notifier).bump();

  void setEnabled(bool enabled) {
    final settings = _ref.read(legacySettingsProvider);
    settings.setSubscriptionAutoUpdateEnabled(enabled);
    _bump();
  }

  bool setIntervalHours(int hours) {
    if (hours < LegacySettings.minSubscriptionAutoUpdateIntervalHours ||
        hours > LegacySettings.maxSubscriptionAutoUpdateIntervalHours) {
      return false;
    }
    final settings = _ref.read(legacySettingsProvider);
    settings.setSubscriptionAutoUpdateIntervalHours(hours);
    settings.setSubscriptionAutoUpdateScheduleRaw(
      AutoUpdateSchedule.interval.storageValue,
    );
    _bump();
    return true;
  }

  void setTimedSchedule(AutoUpdateSchedule schedule, int timeMinutes) {
    assert(schedule.isTimed);
    final settings = _ref.read(legacySettingsProvider);
    settings.setSubscriptionAutoUpdateScheduleRaw(schedule.storageValue);
    settings.setSubscriptionAutoUpdateTimeMinutes(timeMinutes);
    settings.setSubscriptionAutoUpdateSinceMs(
      DateTime.now().millisecondsSinceEpoch,
    );
    _bump();
  }

  Future<void> setGroupEnabled(int groupId, bool enabled) async {
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    await repository?.setGroupAutoUpdateEnabled(groupId, enabled);
  }
}

final autoUpdateActionsProvider = Provider<AutoUpdateActions>(
  AutoUpdateActions.new,
);

final autoUpdateGroupsProvider = FutureProvider<List<SubscriptionGroupRecord>>(
  (ref) => ref.watch(subscriptionGroupsProvider.future),
);
