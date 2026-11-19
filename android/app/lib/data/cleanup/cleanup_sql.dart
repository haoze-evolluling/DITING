library;

import 'package:diting_shared/data/db/datasets.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_android/data/db/preset_whitelist.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

/// Opens each database file once per session: "clear all local data" runs a dozen actions and
/// `AppDatabase.open` re-checks the file every call.
class CleanupDatabases {
  CleanupDatabases(this._open);

  final Future<Database?> Function(String fileName) _open;
  final Map<String, Database?> _cache = {};

  Future<Database?> of(String fileName) async => _cache.containsKey(fileName)
      ? _cache[fileName]
      : (_cache[fileName] = await _open(fileName));

  String get normalRulesFile => DataSet.normal.ruleDatabase;

  String get normalLogsFile => DataSet.normal.logsDatabase;

  /// Normal mode's log database: the only one with `app_traffic_daily`.
  Future<Database?> get main => of(normalLogsFile);

  /// Global automation store, shared by every mode.
  Future<Database?> get app => of(StorageContract.globalDatabase);

  /// Existing rule databases in a fixed order (normal, express), so map iteration order
  /// cannot make tests flaky.
  Future<List<Database>> ruleDatabases() async {
    final databases = <Database>[];
    for (final dataSet in DataSet.values) {
      final db = await of(dataSet.ruleDatabase);
      if (db != null) databases.add(db);
    }
    return databases;
  }

  /// Databases holding runtime tables (logs, cache) in a fixed mode order.
  Future<List<Database>> runtimeDatabases() async {
    final databases = <Database>[];
    for (final dataSet in DataSet.values) {
      final db = await of(dataSet.logsDatabase);
      if (db != null) databases.add(db);
    }
    return databases;
  }

  /// Whether [db] is the normal data set's rule database, the only one cleanup re-seeds.
  bool isMain(Database db) => db.path == _cache[normalRulesFile]?.path;
}

/// Deletes all rows; a missing table returns 0 and logs why.
Future<int> deleteAllRows(DatabaseExecutor db, String table) =>
    _guard(() => db.delete(table), 'delete $table');

/// Deletes matching rows; a missing table or column returns 0.
Future<int> deleteRowsWhere(DatabaseExecutor db, String table, String where) =>
    _guard(() => db.delete(table, where: where), 'delete $table ($where)');

/// Deletes rule rows that no source row references (`NOT EXISTS`).
Future<int> deleteOrphanRows(
  DatabaseExecutor db,
  String ruleTable,
  String sourceTable,
) => deleteRowsWhere(
  db,
  ruleTable,
  'NOT EXISTS (SELECT 1 FROM $sourceTable s WHERE s.ruleId = $ruleTable.id)',
);

/// Zeroes subscription import metadata after the rule tables are cleared. A stale ETag would get a
/// 304 and the rules would never come back.
Future<void> resetSubscriptionImportState(
  DatabaseExecutor db, {
  required String table,
  required Map<String, Object?> values,
}) async {
  try {
    await db.update(table, values);
  } on DatabaseException catch (error) {
    debugPrint('cleanup: subscription reset skipped ($error)');
  }
}

Future<void> deleteOrphanAutoUpdateItems(
  DatabaseExecutor db, {
  required String table,
  required String where,
}) async {
  try {
    await db.delete(table, where: where);
  } on DatabaseException catch (error) {
    debugPrint('cleanup: auto-update orphans skipped ($error)');
  }
}

/// Reads the preset whitelist asset; callers must skip seeding on an empty result or the flag is
/// set with nothing seeded.
Future<List<({String domain, String group})>> loadPresetEntries({
  Future<String> Function()? load,
}) async {
  final asset =
      load ??
      (() => rootBundle.loadString(
        'packages/diting_shared/assets/https_passthrough.txt',
      ));
  try {
    return parsePresetWhitelist(await asset());
  } on FlutterError catch (error) {
    debugPrint('cleanup: preset whitelist asset unavailable ($error)');
    return const [];
  }
}

Future<int> _guard(Future<int> Function() action, String label) async {
  try {
    return await action();
  } on DatabaseException catch (error) {
    debugPrint('cleanup: $label ignored ($error)');
    return 0;
  }
}
