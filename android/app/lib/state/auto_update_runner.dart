library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/state/auto_update_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AutoUpdateSkip {
  disabled,

  noDatabase,

  noSubscriptions,

  notDue,

  busy;

  String label(AppL10n l10n) => switch (this) {
    AutoUpdateSkip.disabled => l10n.autoUpdateDisabled,
    AutoUpdateSkip.noDatabase => l10n.subscriptionDatabaseUnavailable,
    AutoUpdateSkip.noSubscriptions => l10n.autoUpdateNoSubscriptions,
    AutoUpdateSkip.notDue => l10n.autoUpdateNotDue,
    AutoUpdateSkip.busy => l10n.autoUpdateBusy,
  };
}

class AutoUpdateRun {
  const AutoUpdateRun({this.skip, this.summary, this.ranCount = 0, this.dueAt});

  final AutoUpdateSkip? skip;

  final String? summary;

  final int ranCount;

  final int? dueAt;

  bool get didRun => skip == null;
}

class AutoUpdateRunner {
  AutoUpdateRunner(this._ref);

  final Ref _ref;

  static bool isDue(SubscriptionRecord record, int intervalHours, int nowMs) =>
      _intervalPlan(intervalHours).isDue(record, nowMs);

  static int? nextDueAt(
    List<SubscriptionRecord> records,
    int intervalHours,
    int nowMs,
  ) => _intervalPlan(intervalHours).nextDueAt(records, nowMs);

  static AutoUpdatePlan _intervalPlan(int hours) => AutoUpdatePlan(
    schedule: AutoUpdateSchedule.interval,
    intervalHours: hours,
  );

  Future<AutoUpdateRun> runIfDue() async {
    final settings = _ref.read(autoUpdateSettingsProvider);
    if (!settings.enabled) {
      return const AutoUpdateRun(skip: AutoUpdateSkip.disabled);
    }
    final repository = await _ref.read(subscriptionRepositoryProvider.future);
    if (repository == null) {
      return const AutoUpdateRun(skip: AutoUpdateSkip.noDatabase);
    }
    final records = await repository.allAutoUpdatableRemote();
    if (records.isEmpty) {
      return const AutoUpdateRun(skip: AutoUpdateSkip.noSubscriptions);
    }
    final plan = settings.plan;
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = [
      for (final record in records)
        if (plan.isDue(record, now)) record,
    ];
    if (due.isEmpty) {
      return AutoUpdateRun(
        skip: AutoUpdateSkip.notDue,
        dueAt: plan.nextDueAt(records, now),
      );
    }
    if (_ref.read(subscriptionUpdateProvider).isBusy) {
      return const AutoUpdateRun(skip: AutoUpdateSkip.busy);
    }
    final groups = await repository.groups();
    final names = {for (final group in groups) group.id: group.name};
    final entries = [
      for (final record in due)
        SubscriptionEntry(record: record, groupName: names[record.groupId]),
    ];
    await _ref.read(subscriptionUpdateProvider.notifier).updateAll(entries);
    final message = _ref.read(subscriptionUpdateProvider).lastMessage;
    return AutoUpdateRun(
      summary: message ?? currentL10n.autoUpdateChecked(entries.length),
      ranCount: entries.length,
      dueAt: plan.nextDueAt(records, DateTime.now().millisecondsSinceEpoch),
    );
  }
}

final autoUpdateRunnerProvider = Provider<AutoUpdateRunner>(
  AutoUpdateRunner.new,
);

class AutoUpdateLastRunNotifier extends Notifier<AutoUpdateRun?> {
  @override
  AutoUpdateRun? build() => null;

  void record(AutoUpdateRun run) => state = run;
}

final autoUpdateLastRunProvider =
    NotifierProvider<AutoUpdateLastRunNotifier, AutoUpdateRun?>(
      AutoUpdateLastRunNotifier.new,
    );

final autoUpdatableSubscriptionsProvider =
    FutureProvider<List<SubscriptionRecord>>((ref) async {
      ref.watch(subscriptionRevisionProvider);
      final repository = await ref.watch(subscriptionRepositoryProvider.future);
      if (repository == null) {
        return const <SubscriptionRecord>[];
      }
      return repository.allAutoUpdatableRemote();
    });
