library;

import 'dart:io';

import 'package:diting_shared/data/db/legacy_storage_source.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class StorageCopyPlan {
  const StorageCopyPlan({
    required this.target,
    required this.source,
    required this.tables,
  });

  final DatabaseKind target;
  final String source;
  final List<String> tables;
}

List<StorageCopyPlan> storageV2CopyPlans() => [
  StorageCopyPlan(
    target: DatabaseKind.normalRules,
    source: LegacyStorageSource.normalDatabase,
    tables: [
      ...LegacyStorageSource.ruleTables,
      ...LegacyStorageSource.subscriptionTables,
      LegacyStorageSource.ruleVersionTable,
    ],
  ),
  StorageCopyPlan(
    target: DatabaseKind.normalLogs,
    source: LegacyStorageSource.normalDatabase,
    tables: [
      ...LegacyStorageSource.logTables,
      ...LegacyStorageSource.normalExtraTables,
    ],
  ),
  StorageCopyPlan(
    target: DatabaseKind.expressRules,
    source: LegacyStorageSource.expressDatabase,
    tables: [
      ...LegacyStorageSource.ruleTables,
      ...LegacyStorageSource.subscriptionTables,
      LegacyStorageSource.ruleVersionTable,
    ],
  ),
  StorageCopyPlan(
    target: DatabaseKind.expressLogs,
    source: LegacyStorageSource.expressDatabase,
    tables: LegacyStorageSource.logTables,
  ),
  StorageCopyPlan(
    target: DatabaseKind.global,
    source: LegacyStorageSource.normalDatabase,
    tables: LegacyStorageSource.automationTables,
  ),
];

class TableCopyResult {
  const TableCopyResult({
    required this.table,
    required this.sourceRows,
    required this.insertedRows,
    this.sourceMissing = false,
  });

  final String table;
  final int sourceRows;
  final int insertedRows;

  final bool sourceMissing;

  bool get isAppendOnly => _appendOnlyTables.contains(table);

  Map<String, Object?> toJson() => {
    'table': table,
    'sourceRows': sourceRows,
    'insertedRows': insertedRows,
    'sourceMissing': sourceMissing,
  };
}

class StorageCopyResult {
  StorageCopyResult({
    required this.plan,
    required this.tables,
    this.sourceMissing = false,
  });

  final StorageCopyPlan plan;
  final List<TableCopyResult> tables;
  final bool sourceMissing;

  Map<String, Object?> toJson() => {
    'target': plan.target.fileName,
    'source': plan.source,
    'sourceMissing': sourceMissing,
    'tables': [for (final table in tables) table.toJson()],
  };
}

class StorageCopyException implements Exception {
  const StorageCopyException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _appendOnlyTables = <String>{
  'dns_log',
  'dns_race_log',
  'bootstrap_log',
  'http_request_log',
  'app_traffic_daily',
  'automation_event',
  'rule_version',
};

const _batchRows = 5000;

Future<StorageCopyResult> copyStoragePlan(
  Database target,
  String sourcePath,
  StorageCopyPlan plan, {
  void Function(String table, int index, int total)? onTable,
}) async {
  if (!await File(sourcePath).exists()) {
    return StorageCopyResult(
      plan: plan,
      sourceMissing: true,
      tables: [
        for (final table in plan.tables)
          TableCopyResult(
            table: table,
            sourceRows: 0,
            insertedRows: 0,
            sourceMissing: true,
          ),
      ],
    );
  }
  final source = await _openSource(sourcePath);
  if (source == null) {
    throw StorageCopyException('legacy source is unreadable: $sourcePath');
  }
  try {
    await _quickCheck(source, sourcePath);
  } finally {
    await source.close();
  }

  final escaped = _escapePath(sourcePath);
  await target.execute('PRAGMA journal_mode = DELETE');
  await target.execute('PRAGMA synchronous = OFF');
  await target.execute("ATTACH DATABASE '$escaped' AS legacy");
  await target.execute('PRAGMA foreign_keys = OFF');
  final results = <TableCopyResult>[];
  try {
    for (var index = 0; index < plan.tables.length; index++) {
      final table = plan.tables[index];
      onTable?.call(table, index, plan.tables.length);
      results.add(await _copyTable(target, table));
    }
  } finally {
    await _ignoreFailure(() => target.execute('PRAGMA foreign_keys = ON'));
    await _ignoreFailure(() => target.execute('DETACH DATABASE legacy'));
    await _ignoreFailure(() => target.execute('PRAGMA journal_mode = WAL'));
    await _ignoreFailure(() => target.execute('PRAGMA synchronous = NORMAL'));
  }
  return StorageCopyResult(plan: plan, tables: results);
}

Future<Database?> _openSource(String path) async {
  try {
    return await openDatabase(path, readOnly: true, singleInstance: false);
  } on DatabaseException catch (error) {
    debugPrint('legacy source open failed: $path ($error)');
    return null;
  }
}

Future<void> _quickCheck(Database source, String path) async {
  final rows = await source.rawQuery('PRAGMA quick_check');
  final values = rows.isEmpty ? const <Object?>[] : rows.first.values.toList();
  if (values.isEmpty || '${values.first}'.toLowerCase() != 'ok') {
    throw StorageCopyException(
      'legacy source is damaged: $path (${values.join('; ')})',
    );
  }
}

Future<TableCopyResult> _copyTable(DatabaseExecutor executor, String table) async {
  final sourceColumns = await _columns(executor, 'legacy', table);
  if (sourceColumns.isEmpty) {
    return TableCopyResult(
      table: table,
      sourceRows: 0,
      insertedRows: 0,
      sourceMissing: true,
    );
  }
  final targetColumns = await _columns(executor, 'main', table);
  final columns = [
    for (final column in sourceColumns)
      if (targetColumns.contains(column)) column,
  ];
  if (columns.isEmpty) {
    return TableCopyResult(
      table: table,
      sourceRows: await _count(executor, 'legacy', table),
      insertedRows: 0,
    );
  }
  final sourceRows = await _count(executor, 'legacy', table);
  final list = columns.map((column) => '`$column`').join(', ');
  final inserted = columns.contains('id') && await _hasIntegerId(executor, table)
      ? await _copyByid(executor, table, list)
      : await _copyAll(executor, table, list);
  return TableCopyResult(
    table: table,
    sourceRows: sourceRows,
    insertedRows: inserted,
  );
}

Future<int> _copyAll(
  DatabaseExecutor executor,
  String table,
  String columns,
) async {
  await executor.execute(
    'INSERT OR IGNORE INTO main.`$table` ($columns) '
    'SELECT $columns FROM legacy.`$table`',
  );
  return _changes(executor);
}

Future<int> _copyByid(
  DatabaseExecutor executor,
  String table,
  String columns,
) async {
  var last = -1;
  var inserted = 0;
  while (true) {
    final rows = await executor.rawQuery(
      'SELECT id FROM legacy.`$table` WHERE id > ? ORDER BY id LIMIT $_batchRows',
      [last],
    );
    if (rows.isEmpty) break;
    final maxId = (rows.last['id'] as num).toInt();
    await executor.execute(
      'INSERT OR IGNORE INTO main.`$table` ($columns) '
      'SELECT $columns FROM legacy.`$table` WHERE id > ? AND id <= ?',
      [last, maxId],
    );
    inserted += await _changes(executor);
    if (rows.length < _batchRows) break;
    last = maxId;
  }
  return inserted;
}

Future<bool> _hasIntegerId(DatabaseExecutor executor, String table) async {
  final rows = await executor.rawQuery('PRAGMA legacy.table_info(`$table`)');
  for (final row in rows) {
    if (row['name'] != 'id') continue;
    return '${row['type']}'.toLowerCase().contains('int');
  }
  return false;
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

Future<int> _changes(DatabaseExecutor executor) async {
  final rows = await executor.rawQuery('SELECT changes() AS n');
  return (rows.firstOrNull?['n'] as num?)?.toInt() ?? 0;
}

String _escapePath(String path) =>
    path.replaceAll('\\', '/').replaceAll("'", "''");

Future<void> _ignoreFailure(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
  }
}
