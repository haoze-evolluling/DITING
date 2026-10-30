/// When subscriptions fall due: every N hours since the last attempt, or at a local wall-clock
/// time every day / every other day. Pure functions over epoch milliseconds so tests can pin
/// "now"; the wall-clock schedules follow the phone's time zone through [DateTime] local time.
library;

import 'package:diting/data/db/subscription_models.dart';

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
    final last = record.lastAttemptAt;
    if (last <= 0) return true;
    if (!schedule.isTimed) {
      return nowMs - last >= intervalHours * 3600 * 1000;
    }
    final slot = latestSlotAt(nowMs);
    return slot != null && slot >= sinceMs && last < slot;
  }

  /// Next due time (epoch ms); null when no subscription is eligible.
  int? nextDueAt(List<SubscriptionRecord> records, int nowMs) {
    if (records.isEmpty) return null;
    if (records.any((record) => isDue(record, nowMs))) return nowMs;
    if (schedule.isTimed) return nextSlotAfter(nowMs);
    final intervalMs = intervalHours * 3600 * 1000;
    var earliest = nowMs + intervalMs;
    for (final record in records) {
      final due = record.lastAttemptAt + intervalMs;
      if (due < earliest) earliest = due;
    }
    return earliest;
  }

  /// The most recent scheduled moment at or before [nowMs]; null only before the first slot.
  int? latestSlotAt(int nowMs) {
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
    var day = DateTime(now.year, now.month, now.day);
    // Three days back covers the every-other-day gap plus "today's slot has not come yet".
    for (var i = 0; i < 3; i++) {
      if (_isSlotDay(day)) {
        final slot = _slotOn(day);
        if (slot <= nowMs) return slot;
      }
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return null;
  }

  /// The first scheduled moment strictly after [nowMs] (and not before [sinceMs]).
  int nextSlotAfter(int nowMs) {
    final from = nowMs < sinceMs ? sinceMs - 1 : nowMs;
    final now = DateTime.fromMillisecondsSinceEpoch(from);
    var day = DateTime(now.year, now.month, now.day);
    while (true) {
      if (_isSlotDay(day)) {
        final slot = _slotOn(day);
        if (slot > from) return slot;
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }

  bool _isSlotDay(DateTime day) =>
      schedule != AutoUpdateSchedule.everyOtherDay ||
      (localDayNumber(day) - _anchorDay) % 2 == 0;

  /// Day of the first slot at or after [sinceMs]: today when the time has not passed yet.
  int get _anchorDay {
    if (sinceMs <= 0) return 0;
    final since = DateTime.fromMillisecondsSinceEpoch(sinceMs);
    final today = DateTime(since.year, since.month, since.day);
    final day = _slotOn(today) >= sinceMs
        ? today
        : DateTime(today.year, today.month, today.day + 1);
    return localDayNumber(day);
  }

  /// Built from calendar fields, so a DST shift keeps the slot on the chosen wall-clock time.
  int _slotOn(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
    timeMinutes ~/ 60,
    timeMinutes % 60,
  ).millisecondsSinceEpoch;

  /// Days since 1970-01-01 of [time]'s local calendar date, independent of the UTC offset.
  static int localDayNumber(DateTime time) =>
      DateTime.utc(time.year, time.month, time.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
