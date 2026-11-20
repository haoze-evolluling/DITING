library;

import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/subscriptions/rust_subscription_core.dart';

enum AutoUpdateSchedule {
  interval('interval'),
  daily('daily'),
  everyOtherDay('every_other_day');

  const AutoUpdateSchedule(this.storageValue);

  final String storageValue;

  static AutoUpdateSchedule fromStorage(String value) => values.firstWhere(
    (schedule) => schedule.storageValue == value,
    orElse: () => AutoUpdateSchedule.interval,
  );

  bool get isTimed => this != AutoUpdateSchedule.interval;
}

class AutoUpdatePlan {
  const AutoUpdatePlan({
    required this.schedule,
    required this.intervalHours,
    this.timeMinutes = 0,
    this.sinceMs = 0,
  });

  final AutoUpdateSchedule schedule;
  final int intervalHours;

  final int timeMinutes;

  final int sinceMs;

  bool isDue(SubscriptionRecord record, int nowMs) {
    final answer = _evaluate([
      {'id': record.id, 'lastAttemptAt': record.lastAttemptAt},
    ], nowMs);
    return (answer['due'] as List? ?? const []).isNotEmpty;
  }

  int? nextDueAt(List<SubscriptionRecord> records, int nowMs) {
    if (records.isEmpty) return null;
    final answer = _evaluate([
      for (final record in records)
        {'id': record.id, 'lastAttemptAt': record.lastAttemptAt},
    ], nowMs);
    return (answer['nextDueAt'] as num?)?.toInt();
  }

  Map<String, Object?> _evaluate(
    List<Map<String, Object?>> records,
    int nowMs,
  ) {
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
    final since = sinceMs <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sinceMs);
    final nowDay = localDayNumber(now);
    final sinceDay = since == null ? 0 : localDayNumber(since);
    final sinceBeforeDay = since == null
        ? 0
        : localDayNumber(DateTime.fromMillisecondsSinceEpoch(sinceMs - 1));

    final slots = <int, Map<String, Object?>>{};
    void addAround(DateTime anchor) {
      final base = DateTime(anchor.year, anchor.month, anchor.day);
      for (var delta = -3; delta <= 6; delta++) {
        final slot = DateTime(
          base.year,
          base.month,
          base.day + delta,
          timeMinutes ~/ 60,
          timeMinutes % 60,
        );
        final day = localDayNumber(slot);
        slots[day] = {'day': day, 'ms': slot.millisecondsSinceEpoch};
      }
    }

    addAround(now);
    if (since != null) addAround(since);

    return RustSubscriptionCore.instance.call({
      'op': 'schedule.evaluate',
      'schedule': schedule.storageValue,
      'intervalHours': intervalHours,
      'timeMinutes': timeMinutes,
      'sinceMs': sinceMs,
      'nowMs': nowMs,
      'nowDay': nowDay,
      'sinceDay': sinceDay,
      'sinceBeforeDay': sinceBeforeDay,
      'slots': [for (final day in slots.keys.toList()..sort()) slots[day]!],
      'records': records,
    });
  }

  static int localDayNumber(DateTime time) =>
      DateTime.utc(time.year, time.month, time.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
