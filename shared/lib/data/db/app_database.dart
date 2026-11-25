library;

import 'package:diting_shared/data/db/database_schema.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static Future<Database?> open(
    String fileName, {
    bool create = true,
    bool singleInstance = true,
  }) async {
    final kind = DatabaseKind.fromFileName(fileName);
    if (kind == null) {
      throw ArgumentError.value(fileName, 'fileName', 'unknown database');
    }
    final String path;
    try {
      path = p.join(await getDatabasesPath(), fileName);
    } on StateError {
      return null;
    }
    if (!await databaseExists(path)) {
      if (!create) return null;
      return _create(path, kind);
    }
    try {
      final db = await openDatabase(
        path,
        version: StorageContract.schemaVersion,
        onConfigure: _configure,
        singleInstance: singleInstance,
        onUpgrade: (db, from, to) async {
          await _createIfMissing(db, DatabaseSchema.statementsFor(kind));
        },
      );
      final applicationId = await _applicationId(db);
      if (applicationId == kind.applicationId) return db;
      debugPrint(
        'database application id mismatch: $fileName ($applicationId)',
      );
      await db.close();
      if (!create) return null;
      await deleteDatabase(path);
    } on DatabaseException catch (error) {
      debugPrint('database open failed: $fileName ($error)');
      return null;
    }
    return _create(path, kind);
  }

  static Future<Database?> _create(String path, DatabaseKind kind) async {
    final statements = DatabaseSchema.statementsFor(kind);
    try {
      return await openDatabase(
        path,
        version: StorageContract.schemaVersion,
        onConfigure: _configure,
        onCreate: (db, version) async {
          for (final statement in statements) {
            await db.execute(statement);
          }
          await db.execute('PRAGMA application_id = ${kind.applicationId}');
        },
        onUpgrade: (db, from, to) async {
          await _createIfMissing(db, statements);
        },
      );
    } on DatabaseException catch (error) {
      debugPrint('database create failed: ${kind.fileName} ($error)');
      try {
        await deleteDatabase(path);
      } on DatabaseException catch (cleanupError) {
        debugPrint('database cleanup failed: ${kind.fileName} ($cleanupError)');
      }
      return null;
    }
  }

  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA busy_timeout = 5000');
  }

  static Future<int> _applicationId(Database db) async {
    final rows = await db.rawQuery('PRAGMA application_id');
    return (rows.firstOrNull?.values.firstOrNull as num?)?.toInt() ?? 0;
  }

  static Future<void> _createIfMissing(
    Database db,
    List<String> statements,
  ) async {
    for (final statement in statements) {
      try {
        await db.execute(_withIfNotExists(statement));
      } on DatabaseException catch (error) {
        debugPrint('schema patch skipped: $error');
      }
    }
  }

  static String _withIfNotExists(String statement) {
    if (statement.startsWith('CREATE UNIQUE INDEX ')) {
      return statement.replaceFirst(
        'CREATE UNIQUE INDEX ',
        'CREATE UNIQUE INDEX IF NOT EXISTS ',
      );
    }
    if (statement.startsWith('CREATE INDEX ')) {
      return statement.replaceFirst(
        'CREATE INDEX ',
        'CREATE INDEX IF NOT EXISTS ',
      );
    }
    return statement.replaceFirst(
      'CREATE TABLE ',
      'CREATE TABLE IF NOT EXISTS ',
    );
  }
}
