/// Subscription auto-update settings: master switch, schedule (interval or wall-clock time) and
/// per-group switches; nothing is rescheduled natively.
library;

import 'package:diting/data/db/subscription_models.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/state/auto_update_schedule.dart';
import 'package:diting/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:diting/state/auto_update_schedule.dart';

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

  /// Minutes after local midnight, for the timed schedules.
  final int timeMinutes;
  final int sinceMs;

  /// Whether the interval is a preset; drives the custom-interval row highlight.
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

/// Settings writer; bumps the revision so `autoUpdateSettingsProvider` rebuilds.
class AutoUpdateActions {
  AutoUpdateActions(this._ref);

  final Ref _ref;

  void setEnabled(bool enabled) {
    final settings = _ref.read(legacySettingsProvider);
    settings.setSubscriptionAutoUpdateEnabled(enabled);
    // 1.4.3 keeps the chosen interval when the master switch is turned off.
    _ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  /// Rejects intervals outside 1-168 and returns false so the caller can warn. Choosing an
  /// interval also switches the schedule back to interval mode.
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
    _ref.read(legacySettingsRevisionProvider.notifier).bump();
    return true;
  }

  /// Switches to a timed schedule. Restarts the cycle from now, so a slot that already passed
  /// today does not fire the moment the user picks it.
  void setTimedSchedule(AutoUpdateSchedule schedule, int timeMinutes) {
    assert(schedule.isTimed);
    final settings = _ref.read(legacySettingsProvider);
    settings.setSubscriptionAutoUpdateScheduleRaw(schedule.storageValue);
    settings.setSubscriptionAutoUpdateTimeMinutes(timeMinutes);
    settings.setSubscriptionAutoUpdateSinceMs(
      DateTime.now().millisecondsSinceEpoch,
    );
    _ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  /// Group switch, stored in the `subscription_group.autoUpdateEnabled` column.
  Future<void> setGroupEnabled(int groupId, bool enabled) async {
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    await repository?.setGroupAutoUpdateEnabled(groupId, enabled);
  }
}

final autoUpdateActionsProvider = Provider<AutoUpdateActions>(
  AutoUpdateActions.new,
);

/// Groups with their auto-update switch, straight from `subscription_group` rows.
final autoUpdateGroupsProvider = FutureProvider<List<SubscriptionGroupRecord>>(
  (ref) => ref.watch(subscriptionGroupsProvider.future),
);
