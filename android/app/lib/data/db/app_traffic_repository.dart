/// Read access to the legacy `app_traffic_daily` table; rows are written natively. The statements
/// and row defaults live in `rust/diting-log-query-core`.
library;

import 'package:sqflite/sqflite.dart';

import 'package:diting_android/data/db/rust_log_query_core.dart';

class AppTrafficDaily {
  const AppTrafficDaily({
    required this.date,
    required this.packageName,
    required this.appName,
    required this.txBytes,
    required this.rxBytes,
    required this.updatedAt,
  });

  factory AppTrafficDaily.fromParsed(Map<String, Object?> row) =>
      AppTrafficDaily(
        date: row['date'] as String? ?? '',
        packageName: row['packageName'] as String? ?? '',
        appName: row['appName'] as String? ?? '',
        txBytes: (row['txBytes'] as num?)?.toInt() ?? 0,
        rxBytes: (row['rxBytes'] as num?)?.toInt() ?? 0,
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );

  /// `yyyy-MM-dd` in the local zone; the earliest date in the group for the aggregated queries.
  final String date;
  final String packageName;
  final String appName;
  final int txBytes;
  final int rxBytes;
  final int updatedAt;

  int get totalBytes => txBytes + rxBytes;

  /// Share of [total] as 0..1; 0 while the list is still empty.
  double shareOf(int total) => total <= 0 ? 0 : totalBytes / total;

  /// The shape the traffic aggregate consumes.
  Map<String, Object?> toKernel() => {
    'date': date,
    'packageName': packageName,
    'appName': appName,
    'txBytes': txBytes,
    'rxBytes': rxBytes,
    'updatedAt': updatedAt,
  };
}

class AppTrafficRepository {
  AppTrafficRepository(this._db);

  final Database _db;

  Future<List<AppTrafficDaily>> _query(String name, [Map<String, Object?> params = const {}]) async {
    final plan = RustLogQueryCore.instance.plan(name, params);
    final rows = await _db.rawQuery(plan.sql, plan.args);
    return [
      for (final row in RustLogQueryCore.instance.rows('traffic.row', rows))
        AppTrafficDaily.fromParsed(row),
    ];
  }

  Future<List<AppTrafficDaily>> byDate(String date) => _query('traffic.byDate', {'date': date});

  /// Inclusive on both ends; comparing the `yyyy-MM-dd` strings compares dates.
  Future<List<AppTrafficDaily>> dateRange(String startDate, String endDate) =>
      _query('traffic.dateRange', {
        'startDate': startDate,
        'endDate': endDate,
      });

  Future<List<AppTrafficDaily>> allHistory() => _query('traffic.all');

  Future<List<AppTrafficDaily>> today() => byDate(todayKey());

  Future<int> clearAll() => _db.delete('app_traffic_daily');

  /// Local-zone `yyyy-MM-dd`, matching the native ingest key; a UTC key hits the wrong row.
  static String dateKey(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  static String todayKey() => dateKey(DateTime.now());
}
