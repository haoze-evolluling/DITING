library;

import 'package:diting_shared/data/db/datasets.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_android/data/db/preset_whitelist.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

class CleanupDatabases {
  CleanupDatabases(this._open);

  final Future<Database?> Function(String fileName) _open;
  final Map<String, Database?> _cache = {};

  Future<Database?> of(String fileName) async => _cache.containsKey(fileName)
      ? _cache[fileName]
      : (_cache[fileName] = await _open(fileName));

  String get normalRulesFile => DataSet.normal.ruleDatabase;

  String get normalLogsFile => DataSet.normal.logsDatabase;

  Future<Database?> get main => of(normalLogsFile);

  Future<Database?> get app => of(StorageContract.globalDatabase);

  Future<List<Database>> ruleDatabases() async {
    final databases = <Database>[];
    for (final dataSet in DataSet.values) {
      final db = await of(dataSet.ruleDatabase);
      if (db != null) databases.add(db);
    }
    return databases;
  }

  Future<List<Database>> runtimeDatabases() async {
    final databases = <Database>[];
    for (final dataSet in DataSet.values) {
      final db = await of(dataSet.logsDatabase);
      if (db != null) databases.add(db);
    }
    return databases;
  }

  bool isMain(Database db) => db.path == _cache[normalRulesFile]?.path;
}

Future<int> deleteAllRows(DatabaseExecutor db, String table) =>
    _guard(() => db.delete(table), 'delete $table');

Future<int> deleteRowsWhere(DatabaseExecutor db, String table, String where) =>
    _guard(() => db.delete(table, where: where), 'delete $table ($where)');

Future<void> clearColumn(
  DatabaseExecutor db,
  String table,
  String column,
) async {
  try {
    await db.update(table, {column: null});
  } on DatabaseException catch (error) {
    debugPrint('cleanup: clear $table.$column skipped ($error)');
  }
}

Future<int> deleteOrphanRows(
  DatabaseExecutor db,
  String ruleTable,
  String sourceTable,
) => deleteRowsWhere(
  db,
  ruleTable,
  'NOT EXISTS (SELECT 1 FROM $sourceTable s WHERE s.ruleId = $ruleTable.id)',
);

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
