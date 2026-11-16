/// Opens the V2 SQLite stores, creating a missing file from [DatabaseSchema].
library;

import 'dart:io';

import 'package:diting_shared/data/db/database_schema.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  /// Null means [fileName] could neither be opened nor created; callers degrade to "no database".
  ///
  /// [singleInstance] defaults to sqflite's process-wide reuse. Pass `false` to force a brand-new
  /// connection: sqflite keeps its open-database registry in a `static` map shared by every
  /// `FlutterEngine` in the process, so a connection left behind by a previous engine (the app runs
  /// a fresh engine for each re-entered activity while a tunnel service keeps the process alive) is
  /// otherwise handed back to the next one. The startup path uses this to recover from a wedged
  /// connection (see `bootstrapRules`).
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
      // No sqflite implementation on this host (widget tests, desktop): no database. Rule pages
      // then show their empty state instead of crashing before the first frame.
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
      // A file at our path with a foreign header (restored backup, manual copy) is not usable.
      debugPrint('database application id mismatch: $fileName ($applicationId)');
      await db.close();
      if (!create) return null;
      await deleteDatabase(path);
      return _create(path, kind);
    } on DatabaseException catch (error) {
      debugPrint('database open failed: $fileName ($error)');
      return null;
    }
  }

  /// Opens an existing database read-only without running a schema upgrade. Used by the one-time
  /// migrator for the pre-V2 stores.
  static Future<Database?> openSource(String fileName) async {
    final String path;
    try {
      path = p.join(await getDatabasesPath(), fileName);
    } on StateError {
      return null;
    }
    if (!await databaseExists(path)) return null;
    try {
      return await openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );
    } on DatabaseException catch (error) {
      debugPrint('source database open failed: $fileName ($error)');
      return null;
    }
  }

  static Future<void> delete(String fileName) async {
    final String path;
    try {
      path = p.join(await getDatabasesPath(), fileName);
    } on StateError {
      return;
    }
    if (await databaseExists(path)) await deleteDatabase(path);
  }

  static Future<bool> exists(String fileName) async {
    try {
      return await databaseExists(p.join(await getDatabasesPath(), fileName));
    } on StateError {
      return false;
    }
  }

  /// Deletes a database and its WAL/SHM sidecars. Native writers may still hold a connection, so
  /// callers stop the data plane and close native handles first.
  static Future<void> deleteWithSidecars(String directory, String fileName) async {
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File(p.join(directory, '$fileName$suffix'));
      if (await file.exists()) await file.delete();
    }
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
          // A lower user_version means a damaged file; patching beats a reinstall.
          await _createIfMissing(db, statements);
        },
      );
    } on DatabaseException catch (error) {
      debugPrint('database create failed: ${kind.fileName} ($error)');
      // Drop the half-built file, or the next launch opens a database missing tables and fails
      // with "no such column".
      try {
        await deleteDatabase(path);
      } on DatabaseException catch (cleanupError) {
        debugPrint('database cleanup failed: ${kind.fileName} ($cleanupError)');
      }
      return null;
    }
  }

  /// `PRAGMA foreign_keys` is per connection, not stored in the file, so it must be set on every
  /// open; without it `*_source` rows are not cascaded.
  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA busy_timeout = 5000');
  }

  static Future<int> _applicationId(Database db) async {
    final rows = await db.rawQuery('PRAGMA application_id');
    return (rows.firstOrNull?.values.firstOrNull as num?)?.toInt() ?? 0;
  }

  /// Creates only missing tables and indexes; `IF NOT EXISTS` cannot repair a table that exists
  /// with different columns.
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
