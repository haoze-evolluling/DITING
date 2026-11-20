library;

import 'package:diting_shared/data/db/database_schema.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/db/storage_v2_copy.dart';
import 'package:sqflite/sqflite.dart';

class StorageVerifyException implements Exception {
  const StorageVerifyException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Map<String, Object?>> verifyStorageDatabase(
  Database db,
  StorageCopyResult copy,
) async {
  final kind = copy.plan.target;
  final errors = <String>[];

  final integrity = await db.rawQuery('PRAGMA integrity_check');
  final integrityValues = [
    for (final row in integrity) '${row.values.firstOrNull ?? ''}',
  ];
  if (integrityValues.length != 1 ||
      integrityValues.first.toLowerCase() != 'ok') {
    errors.add('integrity_check: ${integrityValues.join('; ')}');
  }

  final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
  if (foreignKeys.isNotEmpty) {
    errors.add('foreign_key_check: ${foreignKeys.length} violation(s)');
  }

  final version = await _pragmaInt(db, 'user_version');
  if (version != StorageContract.schemaVersion) {
    errors.add('user_version: $version');
  }
  final applicationId = await _pragmaInt(db, 'application_id');
  if (applicationId != kind.applicationId) {
    errors.add('application_id: $applicationId');
  }

  final actualTables = await _tables(db);
  final expectedTables = DatabaseSchema.tableNamesFor(kind);
  final extras = actualTables.difference(expectedTables).difference({
    'sqlite_sequence',
    'android_metadata',
  });
  final missing = expectedTables.difference(actualTables);
  if (missing.isNotEmpty) errors.add('missing tables: ${missing.join(', ')}');
  if (extras.isNotEmpty) errors.add('unexpected tables: ${extras.join(', ')}');

  final tables = <Map<String, Object?>>[];
  for (final result in copy.tables) {
    final rows = await _count(db, result.table);
    final same = rows == result.insertedRows;
    if (!same) {
      errors.add(
        '${result.table}: target $rows != inserted ${result.insertedRows}',
      );
    }
    if (result.isAppendOnly && rows != result.sourceRows) {
      errors.add(
        '${result.table}: append-only target $rows != source ${result.sourceRows}',
      );
    }
    tables.add({
      'table': result.table,
      'sourceRows': result.sourceRows,
      'insertedRows': result.insertedRows,
      'targetRows': rows,
      'sourceMissing': result.sourceMissing,
    });
  }

  if (errors.isNotEmpty) {
    throw StorageVerifyException(
      '${kind.fileName}: ${errors.join('; ')}',
    );
  }
  return {
    'target': kind.fileName,
    'source': copy.plan.source,
    'sourceMissing': copy.sourceMissing,
    'tables': tables,
  };
}

Future<int> _pragmaInt(Database db, String name) async {
  final rows = await db.rawQuery('PRAGMA $name');
  return (rows.firstOrNull?.values.firstOrNull as num?)?.toInt() ?? 0;
}

Future<Set<String>> _tables(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return {
    for (final row in rows)
      if (row['name'] is String) row['name'] as String,
  };
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM `$table`');
  return (rows.firstOrNull?['n'] as num?)?.toInt() ?? 0;
}
