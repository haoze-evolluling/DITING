library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/db/app_traffic_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appTrafficRepositoryProvider = FutureProvider<AppTrafficRepository?>((
  ref,
) async {
  if (!ref.watch(workModeProvider).hasTunnelFeatures) return null;
  final db = await ref.watch(activeLogDatabaseProvider.future);
  return db == null ? null : AppTrafficRepository(db);
});

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

class TrafficSnapshot {
  const TrafficSnapshot({
    required this.rows,
    required this.startDate,
    required this.endDate,
    int? txBytes,
    int? rxBytes,
  }) : _kernelTxBytes = txBytes,
       _kernelRxBytes = rxBytes;

  const TrafficSnapshot.empty()
    : rows = const [],
      startDate = '',
      endDate = '',
      _kernelTxBytes = 0,
      _kernelRxBytes = 0;

  final List<AppTrafficDaily> rows;

  final String startDate;
  final String endDate;

  final int? _kernelTxBytes;
  final int? _kernelRxBytes;

  int get txBytes =>
      _kernelTxBytes ?? rows.fold(0, (sum, row) => sum + row.txBytes);

  int get rxBytes =>
      _kernelRxBytes ?? rows.fold(0, (sum, row) => sum + row.rxBytes);

  int get totalBytes => txBytes + rxBytes;

  bool get isEmpty => rows.isEmpty;
}

String _dateKey(DateTime time) => AppTrafficRepository.dateKey(time);

TrafficSnapshot _snapshot(
  List<AppTrafficDaily> rows,
  String startDate,
  String endDate,
) {
  final answer = RustLogQueryCore.instance.derive('traffic.snapshot', {
    'rows': [for (final row in rows) row.toKernel()],
    'startDate': startDate,
    'endDate': endDate,
  });
  return TrafficSnapshot(
    rows: rows,
    startDate: answer['startDate'] as String? ?? startDate,
    endDate: answer['endDate'] as String? ?? endDate,
    txBytes: (answer['txBytes'] as num?)?.toInt() ?? 0,
    rxBytes: (answer['rxBytes'] as num?)?.toInt() ?? 0,
  );
}

Future<TrafficSnapshot> _loadSnapshot(Ref ref, TrafficWindow window) async {
  final repository = await ref.watch(appTrafficRepositoryProvider.future);
  if (repository == null) return const TrafficSnapshot.empty();

  final now = DateTime.now();
  switch (window) {
    case TrafficWindow.today:
      final key = _dateKey(now);
      return _snapshot(await repository.byDate(key), key, key);
    case TrafficWindow.week:
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final start = _dateKey(monday);
      final end = _dateKey(now);
      return _snapshot(await repository.dateRange(start, end), start, end);
    case TrafficWindow.month:
      final start = _dateKey(DateTime(now.year, now.month));
      final end = _dateKey(now);
      return _snapshot(await repository.dateRange(start, end), start, end);
    case TrafficWindow.all:
      return _snapshot(await repository.allHistory(), '', '');
  }
}

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

final trafficSnapshotProvider = FutureProvider<TrafficSnapshot>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final window = ref.watch(trafficWindowProvider);
  return _loadSnapshot(ref, window);
});

final trafficSnapshotOfProvider =
    FutureProvider.family<TrafficSnapshot, TrafficWindow>((ref, window) {
      ref.watch(dnsLogRevisionProvider);
      return _loadSnapshot(ref, window);
    });

const trafficHideSystemAppsKey = 'traffic_stats_hide_system_apps';

class TrafficHideSystemAppsNotifier extends Notifier<bool> {
  @override
  bool build() {
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

class TrafficClearHistoryNotifier extends Notifier<AsyncValue<int?>> {
  @override
  AsyncValue<int?> build() => const AsyncValue<int?>.data(null);

  Future<int> clear() async {
    state = const AsyncValue<int?>.loading();
    try {
      final repository = await ref.read(appTrafficRepositoryProvider.future);
      final deleted = await repository?.clearAll() ?? 0;
      state = AsyncValue<int?>.data(deleted);
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
