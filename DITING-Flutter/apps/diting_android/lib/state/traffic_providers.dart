/// Traffic statistics from the legacy `app_traffic_daily` table, written natively by
/// `TrafficIngest`; rows are per day.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/app_traffic_repository.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Read-only repository; null before the database exists, so callers render an empty state.
final appTrafficRepositoryProvider = FutureProvider<AppTrafficRepository?>((
  ref,
) async {
  final db = await ref.watch(mainLogDatabaseProvider.future);
  return db == null ? null : AppTrafficRepository(db);
});

/// Selectable windows with a real backend; `SESSION` and `REALTIME_SPEED` are excluded.
enum TrafficWindow {
  today,
  week,
  month,
  all;

  String label(AppL10n l10n) => switch (this) {
    TrafficWindow.today => l10n.commonToday,
    TrafficWindow.week => l10n.trafficWindowWeek,
    TrafficWindow.month => l10n.trafficWindowMonth,
    TrafficWindow.all => l10n.commonAll,
  };
}

class TrafficWindowNotifier extends Notifier<TrafficWindow> {
  @override
  TrafficWindow build() => TrafficWindow.today;

  void select(TrafficWindow window) {
    if (state == window) return;
    state = window;
  }
}

final trafficWindowProvider =
    NotifierProvider<TrafficWindowNotifier, TrafficWindow>(
      TrafficWindowNotifier.new,
    );

/// Rows aggregated by package plus window totals, computed here so the page cannot fold them twice.
class TrafficSnapshot {
  const TrafficSnapshot({
    required this.rows,
    required this.startDate,
    required this.endDate,
  });

  const TrafficSnapshot.empty() : rows = const [], startDate = '', endDate = '';

  /// Sorted by total bytes, matching the SQL `ORDER BY`.
  final List<AppTrafficDaily> rows;

  /// First and last date of the window (`yyyy-MM-dd`); identical for today.
  final String startDate;
  final String endDate;

  int get txBytes => rows.fold(0, (sum, row) => sum + row.txBytes);

  int get rxBytes => rows.fold(0, (sum, row) => sum + row.rxBytes);

  int get totalBytes => txBytes + rxBytes;

  bool get isEmpty => rows.isEmpty;
}

String _dateKey(DateTime time) => AppTrafficRepository.dateKey(time);

Future<TrafficSnapshot> _loadSnapshot(Ref ref, TrafficWindow window) async {
  final repository = await ref.watch(appTrafficRepositoryProvider.future);
  if (repository == null) return const TrafficSnapshot.empty();

  // `weekday - 1` walks back to Monday: this is the calendar week, not "last 7 days".
  final now = DateTime.now();
  switch (window) {
    case TrafficWindow.today:
      final key = _dateKey(now);
      return TrafficSnapshot(
        rows: await repository.byDate(key),
        startDate: key,
        endDate: key,
      );
    case TrafficWindow.week:
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final start = _dateKey(monday);
      final end = _dateKey(now);
      return TrafficSnapshot(
        rows: await repository.dateRange(start, end),
        startDate: start,
        endDate: end,
      );
    case TrafficWindow.month:
      final start = _dateKey(DateTime(now.year, now.month));
      final end = _dateKey(now);
      return TrafficSnapshot(
        rows: await repository.dateRange(start, end),
        startDate: start,
        endDate: end,
      );
    case TrafficWindow.all:
      return TrafficSnapshot(
        rows: await repository.allHistory(),
        startDate: '',
        endDate: '',
      );
  }
}

/// Sort modes computable from the daily table; `REALTIME_SPEED` has no data source.
enum TrafficSort {
  total,
  download,
  upload;

  String label(AppL10n l10n) => switch (this) {
    TrafficSort.total => l10n.trafficSortTotal,
    TrafficSort.download => l10n.trafficSortDownload,
    TrafficSort.upload => l10n.trafficSortUpload,
  };
}

class TrafficSortNotifier extends Notifier<TrafficSort> {
  @override
  TrafficSort build() => TrafficSort.total;

  void select(TrafficSort sort) {
    if (state == sort) return;
    state = sort;
  }
}

final trafficSortProvider = NotifierProvider<TrafficSortNotifier, TrafficSort>(
  TrafficSortNotifier.new,
);

class TrafficSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    if (state == query) return;
    state = query;
  }
}

final trafficSearchProvider = NotifierProvider<TrafficSearchNotifier, String>(
  TrafficSearchNotifier.new,
);

/// Real data for the current window.
final trafficSnapshotProvider = FutureProvider<TrafficSnapshot>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final window = ref.watch(trafficWindowProvider);
  return _loadSnapshot(ref, window);
});

/// A fixed window, for cards that pick their own range without moving the traffic page's.
final trafficSnapshotOfProvider =
    FutureProvider.family<TrafficSnapshot, TrafficWindow>((ref, window) {
      ref.watch(dnsLogRevisionProvider);
      return _loadSnapshot(ref, window);
    });

/// Set after the first visit to the traffic page; the live-rate note and the attribution
/// banner show only on that visit (the app bar info button still opens the explainer).
const trafficTipsSeenKey = 'traffic_stats_tips_seen';

/// Returns whether the traffic page tips are still unseen, and marks them seen.
bool consumeTrafficTips(LegacyPrefsStore store) {
  final seen =
      store.read(LegacySettings.uiContainer, trafficTipsSeenKey) == true;
  if (!seen) {
    store.putBool(LegacySettings.uiContainer, trafficTipsSeenKey, true);
  }
  return !seen;
}

// Hide system apps (1.4.3 `SystemSettingsStore.isTrafficStatsHideSystemApps`).

/// `traffic_stats_hide_system_apps`, same key and container as legacy.
const trafficHideSystemAppsKey = 'traffic_stats_hide_system_apps';

/// Hide-system-apps switch, false by default like the legacy store.
class TrafficHideSystemAppsNotifier extends Notifier<bool> {
  @override
  bool build() {
    // The write path bumps this revision; readers rebuild to see new values.
    ref.watch(legacySettingsRevisionProvider);
    final stored = ref
        .watch(legacyPrefsStoreProvider)
        .read(LegacySettings.uiContainer, trafficHideSystemAppsKey);
    return stored is bool ? stored : false;
  }

  void setValue(bool value) {
    if (state == value) return;
    ref
        .read(legacyPrefsStoreProvider)
        .putBool(LegacySettings.uiContainer, trafficHideSystemAppsKey, value);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
    state = value;
  }
}

final trafficHideSystemAppsProvider =
    NotifierProvider<TrafficHideSystemAppsNotifier, bool>(
      TrafficHideSystemAppsNotifier.new,
    );

/// Clears all traffic history and returns the row count; a missing database returns 0, not a throw.
class TrafficClearHistoryNotifier extends Notifier<AsyncValue<int?>> {
  @override
  AsyncValue<int?> build() => const AsyncValue<int?>.data(null);

  Future<int> clear() async {
    state = const AsyncValue<int?>.loading();
    try {
      final repository = await ref.read(appTrafficRepositoryProvider.future);
      final deleted = await repository?.clearAll() ?? 0;
      state = AsyncValue<int?>.data(deleted);
      // Ranking and totals must re-query; stale rows would stay in the snapshot.
      ref.read(dnsLogRevisionProvider.notifier).bump();
      return deleted;
    } catch (error, stack) {
      state = AsyncValue<int?>.error(error, stack);
      rethrow;
    }
  }
}

final trafficClearHistoryProvider =
    NotifierProvider<TrafficClearHistoryNotifier, AsyncValue<int?>>(
      TrafficClearHistoryNotifier.new,
    );
