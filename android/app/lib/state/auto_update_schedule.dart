/// When subscriptions fall due: every N hours since the last attempt, or at a local wall-clock
/// time every day / every other day.
///
/// The decision rules — the 3-day look-back, the anchor day, every-other-day parity and "due from
/// `lastAttemptAt`, not `lastUpdated`" — live in `rust/diting-subscription-core/src/schedule.rs`.
/// This file only converts the local calendar around `now` and `since` into a `day → slot` table:
/// `DateTime` is the one piece the kernel cannot own, and the table is what keeps DST handling
/// exactly as the legacy implementation had it.
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

/// The schedule plus the values each mode needs; [timeMinutes] and [sinceMs] only matter for
/// the timed modes.
class AutoUpdatePlan {
  const AutoUpdatePlan({
    required this.schedule,
    required this.intervalHours,
    this.timeMinutes = 0,
    this.sinceMs = 0,
  });

  final AutoUpdateSchedule schedule;
  final int intervalHours;

  /// Minutes after local midnight.
  final int timeMinutes;

  /// When the timed schedule was last chosen or retimed. Slots before it do not count, so picking
  /// 04:00 at noon waits for tomorrow instead of firing at once; every-other-day counts its cycle
  /// from the first slot at or after it.
  final int sinceMs;

  /// Due from `lastAttemptAt`, not `lastUpdated`: a 304-only row would otherwise look due forever.
  bool isDue(SubscriptionRecord record, int nowMs) {
    final answer = _evaluate([
      {'id': record.id, 'lastAttemptAt': record.lastAttemptAt},
    ], nowMs);
    return (answer['due'] as List? ?? const []).isNotEmpty;
  }

  /// Next due time (epoch ms); null when no subscription is eligible.
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

    // The kernel needs the last three days (look-back), the next few (next slot) and both sides
    // of `since` (anchor). Building a fixed window around each anchor keeps every lookup local.
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

  /// Days since 1970-01-01 of [time]'s local calendar date, independent of the UTC offset.
  static int localDayNumber(DateTime time) =>
      DateTime.utc(time.year, time.month, time.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
