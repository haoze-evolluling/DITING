/// Foreground catch-up for 1.4.3 `executePeriodic`: runs on start, on resume and at the next due
/// moment while the app stays in the foreground, as there is no WorkManager.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/db/subscription_models.dart';
import 'package:diting/state/auto_update_providers.dart';
import 'package:diting/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AutoUpdateSkip {
  disabled,

  /// Legacy DB missing (fresh install).
  noDatabase,

  /// No eligible subscriptions (remote, enabled, group allowed).
  noSubscriptions,

  notDue,

  /// A manual update is running; yield (1.4.3 `BlockedByManualOperation`).
  busy;

  String label(AppL10n l10n) => switch (this) {
    AutoUpdateSkip.disabled => l10n.autoUpdateDisabled,
    AutoUpdateSkip.noDatabase => l10n.subscriptionDatabaseUnavailable,
    AutoUpdateSkip.noSubscriptions => l10n.autoUpdateNoSubscriptions,
    AutoUpdateSkip.notDue => l10n.autoUpdateNotDue,
    AutoUpdateSkip.busy => l10n.autoUpdateBusy,
  };
}

/// Result of one check; a null [skip] means a real run happened.
class AutoUpdateRun {
  const AutoUpdateRun({this.skip, this.summary, this.ranCount = 0, this.dueAt});

  /// Why the run was skipped; null when it executed.
  final AutoUpdateSkip? skip;

  /// Run summary, e.g. "3 updated, 1 unchanged".
  final String? summary;

  final int ranCount;

  /// Next due time (epoch ms) for the "next update" label.
  final int? dueAt;

  bool get didRun => skip == null;
}

class AutoUpdateRunner {
  AutoUpdateRunner(this._ref);

  final Ref _ref;

  /// Interval-mode shortcuts kept for callers and tests; see [AutoUpdatePlan].
  static bool isDue(SubscriptionRecord record, int intervalHours, int nowMs) =>
      _intervalPlan(intervalHours).isDue(record, nowMs);

  /// Next due time (epoch ms); null when no subscription is eligible.
  static int? nextDueAt(
    List<SubscriptionRecord> records,
    int intervalHours,
    int nowMs,
  ) => _intervalPlan(intervalHours).nextDueAt(records, nowMs);

  static AutoUpdatePlan _intervalPlan(int hours) => AutoUpdatePlan(
    schedule: AutoUpdateSchedule.interval,
    intervalHours: hours,
  );

  /// Never throws: lifecycle callbacks drive it, so an exception would red-screen on every resume.
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
    // Mutually exclusive with manual updates: yield now, catch up next round.
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

/// Eligible subscriptions (remote, enabled, group allowed) for the "next update" label.
final autoUpdatableSubscriptionsProvider =
    FutureProvider<List<SubscriptionRecord>>((ref) async {
      ref.watch(subscriptionRevisionProvider);
      final repository = await ref.watch(subscriptionRepositoryProvider.future);
      if (repository == null) {
        return const <SubscriptionRecord>[];
      }
      return repository.allAutoUpdatableRemote();
    });
