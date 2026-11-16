// The split-layout migration: every legacy row is copied, the marker is written only after the
// counts verify, and running it twice cannot duplicate rows or touch the legacy files.

import 'dart:io';

import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/db/storage_migration.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late MemoryLegacyPrefsStore store;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('diting-storage-');
    await databaseFactory.setDatabasesPath(directory.path);
    store = MemoryLegacyPrefsStore({
      'diting_settings': const {},
      'dns_vpn_prefs': const {},
    });
  });

  tearDown(() async {
    // The migrator intentionally leaves its handles open for the app; close them before the temp
    // directory can be removed on Windows.
    for (final name in StorageContract.allKnownDatabases) {
      final db = await LegacyDatabase.open(name, create: false);
      if (db != null) await db.close();
    }
    await directory.delete(recursive: true);
  });

  Future<Database> openLegacy(String name) =>
      LegacyDatabase.open(name).then((db) {
        if (db == null) throw StateError('cannot open $name');
        return db;
      });

  test('旧库规则、日志、自动化分别复制到目标库', () async {
    final main = await openLegacy(LegacyDatabase.mainFile);
    await main.insert('block_rule', {
      'pattern': 'ads.example',
      'rawLine': '||ads.example^',
      'addedAt': 1,
      'enabled': 1,
      'important': 0,
      'appInverted': 0,
      'isWildcard': 0,
      'isRegex': 0,
    });
    await main.insert('subscription', {
      'url': 'https://example.test/list.txt',
      'name': '测试订阅',
      'sourceType': 'remote',
      'kind': 'domain',
      'enabled': 1,
      'ruleCount': 1,
      'lastUpdated': 1,
      'addedAt': 1,
      'importState': 'done',
      'lastAttemptAt': 1,
      'consecutiveFailureCount': 0,
      'mirrorFallback': 0,
    });
    await main.insert('dns_log', {
      'timestamp': 10,
      'queryName': 'ads.example',
      'queryType': 1,
      'result': 'BLOCKED',
      'cached': 0,
    });
    await main.insert('http_request_log', {
      'timestamp': 11,
      'packageName': 'com.example',
      'protocol': 'h2',
      'outcome': 'blocked',
    });
    await main.insert('app_traffic_daily', {
      'date': '2026-11-16',
      'package_name': 'com.example',
      'app_name': '示例',
      'tx_bytes': 1,
      'rx_bytes': 2,
      'updated_at': 1,
    });
    await main.insert('automation_rule', {
      'id': 'rule-1',
      'name': '夜间暂停',
      'enabled': 1,
      'priority': 100,
      'match': 'all',
      'spec_json': '{}',
      'last_run_at': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await main.close();

    final express = await openLegacy(LegacyDatabase.expressFile);
    await express.insert('block_rule', {
      'pattern': 'express.example',
      'rawLine': 'express.example',
      'addedAt': 1,
      'enabled': 1,
      'important': 0,
      'appInverted': 0,
      'isWildcard': 0,
      'isRegex': 0,
    });
    await express.insert('dns_log', {
      'timestamp': 12,
      'queryName': 'express.example',
      'queryType': 1,
      'result': 'PASSED',
      'cached': 0,
    });
    await express.close();

    final serverLogs = await openLegacy(LegacyDatabase.serverLogFile);
    await serverLogs.insert('dns_log', {
      'timestamp': 13,
      'queryName': 'lan.example',
      'queryType': 1,
      'result': 'PASSED',
      'cached': 0,
    });
    await serverLogs.close();

    final result = await ensureSplitStorage(store);

    expect(result.split, isTrue, reason: result.error);
    expect(
      store.read(
        LegacySettings.workModeContainer,
        StorageContract.layoutVersionKey,
      ),
      StorageLayout.splitVersion,
    );

    final normalRules = await openLegacy(LegacyDatabase.normalRulesFile);
    expect(await _count(normalRules, 'block_rule'), 1);
    expect(await _count(normalRules, 'subscription'), 1);
    expect(await _hasTable(normalRules, 'dns_log'), isFalse);
    await normalRules.close();

    final normalLogs = await openLegacy(LegacyDatabase.normalLogsFile);
    expect(await _count(normalLogs, 'dns_log'), 1);
    expect(await _count(normalLogs, 'http_request_log'), 1);
    expect(await _count(normalLogs, 'app_traffic_daily'), 1);
    expect(await _hasTable(normalLogs, 'block_rule'), isFalse);
    await normalLogs.close();

    final expressRules = await openLegacy(LegacyDatabase.expressRulesFile);
    expect(await _count(expressRules, 'block_rule'), 1);
    await expressRules.close();

    final expressLogs = await openLegacy(LegacyDatabase.expressLogsFile);
    expect(await _count(expressLogs, 'dns_log'), 1);
    await expressLogs.close();

    final serverLogTarget = await openLegacy(LegacyDatabase.serverLogsFile);
    expect(await _count(serverLogTarget, 'dns_log'), 1);
    await serverLogTarget.close();

    final app = await openLegacy(LegacyDatabase.appFile);
    expect(await _count(app, 'automation_rule'), 1);
    await app.close();

    // Copy-only: the legacy combined file still has all of its rows.
    final legacy = await openLegacy(LegacyDatabase.mainFile);
    expect(await _count(legacy, 'dns_log'), 1);
    expect(await _count(legacy, 'block_rule'), 1);
    await legacy.close();

    // A second run is a no-op, not a duplicate import.
    final again = await ensureSplitStorage(store);
    expect(again.split, isTrue);
    final reopened = await openLegacy(LegacyDatabase.normalRulesFile);
    expect(await _count(reopened, 'block_rule'), 1);
    await reopened.close();
  });

  test('数据平面运行中时推迟迁移，不改布局标记', () async {
    final result = await ensureSplitStorage(store, dataPlaneRunning: true);

    expect(result.split, isFalse);
    expect(result.deferred, isTrue);
    expect(
      store.read(
        LegacySettings.workModeContainer,
        StorageContract.layoutVersionKey,
      ),
      isNull,
    );
  });

  test('没有旧库时建立空的拆分库并写入标记', () async {
    final result = await ensureSplitStorage(store);

    expect(result.split, isTrue, reason: result.error);
    const expected = {
      LegacyDatabase.normalRulesFile: 'block_rule',
      LegacyDatabase.normalLogsFile: 'dns_log',
      LegacyDatabase.expressRulesFile: 'block_rule',
      LegacyDatabase.expressLogsFile: 'dns_log',
      LegacyDatabase.serverFile: 'block_rule',
      LegacyDatabase.serverLogsFile: 'dns_log',
      LegacyDatabase.appFile: 'automation_rule',
    };
    for (final entry in expected.entries) {
      final db = await openLegacy(entry.key);
      expect(await _hasTable(db, entry.value), isTrue, reason: entry.key);
      await db.close();
    }
  });
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM `$table`');
  return (rows.first['n'] as num?)?.toInt() ?? 0;
}

Future<bool> _hasTable(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return rows.isNotEmpty;
}
