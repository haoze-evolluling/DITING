/// One-time copy from the combined legacy databases into the split layout.
///
/// The migration is additive: the legacy files are never modified, every row is copied with its
/// original id, and `storage_layout_version` is written only after every target table has at least
/// the source row count. A failure anywhere leaves the marker untouched, so the next launch keeps
/// using the legacy files and retries.
library;

import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/db/legacy_schema.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class StorageMigrationResult {
  const StorageMigrationResult._({
    required this.split,
    this.error,
    this.deferred = false,
  });

  const StorageMigrationResult.ready() : this._(split: true);

  factory StorageMigrationResult.skipped(Object error) =>
      StorageMigrationResult._(split: false, error: '$error');

  /// Valid reason not to copy yet (a data plane is running); not a fault.
  factory StorageMigrationResult.deferred(String reason) =>
      StorageMigrationResult._(split: false, error: reason, deferred: true);

  /// True when the split layout is active after this call.
  final bool split;

  /// Why the copy was skipped; the legacy layout stays active so nothing is lost.
  final String? error;

  /// The copy will be retried on a later launch without any error to report.
  final bool deferred;
}

/// One target store and the legacy file its rows come from.
typedef _CopyPlan = ({String? source, List<String> tables});

/// Creates the split stores and copies every existing row into them.
///
/// Safe to call on every launch: once [StorageContract.layoutVersionKey] is at
/// [StorageLayout.splitVersion] it returns immediately. A partially completed earlier attempt is
/// retried with `INSERT OR IGNORE`, and ids are copied explicitly so retries cannot duplicate rows.
Future<StorageMigrationResult> ensureSplitStorage(
  LegacyPrefsStore store, {
  bool dataPlaneRunning = false,
}) async {
  final settings = LegacySettings(store);
  final stopwatch = Stopwatch()..start();
  if (settings.storageLayout.isSplit) {
    // Installs that split before the completion key existed get the timestamp backfilled, so the
    // legacy-reclaim grace period starts now instead of never.
    if (settings.storageSplitCompletedAt == null) {
      settings.setStorageSplitCompletedAt(DateTime.now());
    }
    if (settings.storageMigrationError != null) {
      settings.setStorageMigrationError(null);
    }
    return const StorageMigrationResult.ready();
  }
  // A running data plane keeps its legacy file handles until restart. Copying now would leave the
  // rows it writes during this session only in the old file, so defer to a later launch.
  if (dataPlaneRunning) {
    const reason = 'a running data plane keeps the legacy databases in use';
    settings.setStorageMigrationError(reason);
    return StorageMigrationResult.deferred(reason);
  }
  try {
    final directory = await getDatabasesPath();
    final plans = <String, _CopyPlan>{
      LegacyDatabase.normalRulesFile: (
        source: LegacyDatabase.mainFile,
        tables: [
          ...LegacySchema.ruleTableNames,
          ...LegacySchema.subscriptionTableNames,
        ],
      ),
      LegacyDatabase.normalLogsFile: (
        source: LegacyDatabase.mainFile,
        tables: [
          ...LegacySchema.migrationLogTableNames,
          ...LegacySchema.httpTrafficTableNames,
        ],
      ),
      LegacyDatabase.expressRulesFile: (
        source: LegacyDatabase.expressFile,
        tables: [
          ...LegacySchema.ruleTableNames,
          ...LegacySchema.subscriptionTableNames,
        ],
      ),
      LegacyDatabase.expressLogsFile: (
        source: LegacyDatabase.expressFile,
        tables: LegacySchema.migrationLogTableNames,
      ),
      LegacyDatabase.serverLogsFile: (
        source: LegacyDatabase.serverLogFile,
        tables: LegacySchema.migrationLogTableNames,
      ),
      LegacyDatabase.appFile: (
        source: LegacyDatabase.mainFile,
        tables: LegacySchema.automationTableNames,
      ),
    };

    for (final entry in plans.entries) {
      final target = await LegacyDatabase.open(entry.key);
      if (target == null) {
        throw StateError('cannot open ${entry.key}');
      }
      final source = entry.value.source;
      if (source == null) continue;
      final sourcePath = p.join(directory, source);
      if (!await databaseExists(sourcePath)) continue;
      await _copyFrom(target, sourcePath, entry.value.tables);
    }

    // The server rules file was already rule-only; opening it makes a fresh install complete too.
    if (await LegacyDatabase.open(LegacyDatabase.serverFile) == null) {
      throw StateError('cannot open ${LegacyDatabase.serverFile}');
    }

    // Commit point: wait for the platform to accept the marker before reporting the split layout.
    // Native services resolve file names from this same store, so a fire-and-forget write could
    // leave Dart on the new files while a tunnel started in this session keeps writing the old one.
    await settings.commitStorageLayoutVersion(StorageLayout.splitVersion);
    if (settings.storageSplitCompletedAt == null) {
      settings.setStorageSplitCompletedAt(DateTime.now());
    }
    settings.setStorageMigrationError(null);
    debugPrint(
      'storage migration complete in ${stopwatch.elapsedMilliseconds}ms',
    );
    return const StorageMigrationResult.ready();
  } catch (error) {
    debugPrint('storage migration skipped; keeping legacy layout: $error');
    settings.setStorageMigrationError('$error');
    return StorageMigrationResult.skipped(error);
  }
}

Future<void> _copyFrom(
  Database target,
  String sourcePath,
  List<String> tables,
) async {
  // SQLite accepts forward slashes on every platform; Windows backslashes are not portable here.
  final escaped = sourcePath.replaceAll('\\', '/').replaceAll("'", "''");
  await target.execute('PRAGMA busy_timeout = 5000');
  await target.execute("ATTACH DATABASE '$escaped' AS legacy");
  try {
    // Rule source tables reference their parent rows; copy order is not guaranteed to satisfy the
    // foreign keys, so they are checked by the app, not by SQLite during the copy.
    await target.execute('PRAGMA foreign_keys = OFF');
    final copied = <String>[];
    await target.transaction((txn) async {
      for (final table in tables) {
        if (await _copyTable(txn, table)) copied.add(table);
      }
    });
    for (final table in copied) {
      final sourceRows = await _count(target, 'legacy', table);
      final targetRows = await _count(target, 'main', table);
      if (targetRows < sourceRows) {
        throw StateError(
          '$table copied $targetRows of $sourceRows rows from $sourcePath',
        );
      }
    }
  } finally {
    await _ignoreFailure(() => target.execute('PRAGMA foreign_keys = ON'));
    await _ignoreFailure(() => target.execute('DETACH DATABASE legacy'));
  }
}

Future<bool> _copyTable(DatabaseExecutor executor, String table) async {
  final sourceColumns = await _columns(executor, 'legacy', table);
  if (sourceColumns.isEmpty) return false;
  final targetColumns = await _columns(executor, 'main', table);
  final columns = [
    for (final column in sourceColumns)
      if (targetColumns.contains(column)) column,
  ];
  if (columns.isEmpty) return false;
  final list = columns.map((column) => '`$column`').join(', ');
  await executor.execute(
    'INSERT OR IGNORE INTO main.`$table` ($list) '
    'SELECT $list FROM legacy.`$table`',
  );
  return true;
}

Future<Set<String>> _columns(
  DatabaseExecutor executor,
  String schema,
  String table,
) async {
  final rows = await executor.rawQuery('PRAGMA $schema.table_info(`$table`)');
  return {
    for (final row in rows)
      if (row['name'] is String) row['name'] as String,
  };
}

Future<int> _count(
  DatabaseExecutor executor,
  String schema,
  String table,
) async {
  final rows = await executor.rawQuery(
    'SELECT COUNT(*) AS n FROM `$schema`.`$table`',
  );
  return (rows.firstOrNull?['n'] as num?)?.toInt() ?? 0;
}

/// Best effort for cleanup steps that must not mask the original failure.
Future<void> _ignoreFailure(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    // The connection is going away or the copy already failed.
  }
}
