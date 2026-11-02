/// Opens the three legacy SQLite databases, creating missing ones from [LegacySchema].
library;

import 'package:diting_shared/data/db/legacy_schema.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LegacyDatabase {
  LegacyDatabase._();

  /// Full-tunnel database, `user_version` 3.
  static const mainFile = 'diting_database';

  /// Express-mode database, `user_version` 2.
  static const expressFile = 'diting_express';

  /// Server-mode rules database, `user_version` 3.
  static const serverFile = 'diting_dns_rules';

  /// Null means [fileName] could neither be opened nor created; callers degrade to "no rule
  /// database".
  static Future<Database?> open(String fileName, {bool create = true}) async {
    final String path;
    try {
      path = p.join(await getDatabasesPath(), fileName);
    } on StateError {
      // No sqflite implementation on this host (widget tests, desktop): no rule database. Rule
      // pages then show their empty state instead of crashing before the first frame.
      return null;
    }
    if (!await databaseExists(path)) {
      if (!create) return null;
      return _create(path, fileName);
    }
    try {
      return await openDatabase(path, onConfigure: _configure);
    } on DatabaseException catch (error) {
      debugPrint('legacy database open failed: $fileName ($error)');
      return null;
    }
  }

  /// `PRAGMA foreign_keys` is per connection, not stored in the file, so it must be set on every
  /// open; without it `*_source` rows are not cascaded.
  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<Database?> _create(String path, String fileName) async {
    final statements = LegacySchema.statementsFor(fileName);
    try {
      return await openDatabase(
        path,
        version: LegacySchema.versionOf(fileName),
        onConfigure: _configure,
        onCreate: (db, version) async {
          for (final statement in statements) {
            await db.execute(statement);
          }
        },
        onUpgrade: (db, from, to) async {
          // A lower `user_version` means a damaged file; patching beats a reinstall.
          await _createIfMissing(db, statements);
        },
      );
    } on DatabaseException catch (error) {
      debugPrint('legacy database create failed: $fileName ($error)');
      // Drop the half-built file, or the next launch opens a database missing tables and fails with
      // "no such column".
      try {
        await deleteDatabase(path);
      } on DatabaseException catch (cleanupError) {
        debugPrint('legacy database cleanup failed: $fileName ($cleanupError)');
      }
      return null;
    }
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
        debugPrint('legacy schema patch skipped: $error');
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
