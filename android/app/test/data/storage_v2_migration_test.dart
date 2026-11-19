// The V2 migration: legacy rows are copied into five new stores, verified, and only then are the
// old files removed. Interrupted or failed runs keep the old files and leave the marker unset.

import 'dart:io';
import 'dart:typed_data';

import 'package:diting_shared/data/db/app_database.dart';
import 'package:diting_shared/data/db/database_schema.dart';
import 'package:diting_shared/data/db/legacy_storage_source.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/db/storage_v2_migration.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late MemoryLegacyPrefsStore store;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('diting-v2-');
    await databaseFactory.setDatabasesPath(directory.path);
    store = MemoryLegacyPrefsStore({
      StorageContract.settingsContainer: const {},
    });
  });

  tearDown(() async {
    for (final kind in DatabaseKind.values) {
      final db = await AppDatabase.open(kind.fileName, create: false);
      if (db != null) await db.close();
    }
    await directory.delete(recursive: true);
  });

  Future<Database> createLegacy(
    String name,
    List<DatabaseKind> kinds,
  ) async {
    final path = p.join(directory.path, name);
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          for (final kind in kinds) {
            for (final statement in DatabaseSchema.statementsFor(kind)) {
              await db.execute(statement);
            }
          }
        },
      ),
    );
  }

  Future<void> seedNormal(Database db) async {
    await db.insert('block_rule', {
      'pattern': 'ads.example',
      'rawLine': '||ads.example^',
      'addedAt': 1,
      'enabled': 1,
      'important': 0,
      'appInverted': 0,
      'isWildcard': 0,
      'isRegex': 0,
    });
    await db.insert('block_rule_source', {
      'ruleId': 1,
      'source': 'useradd',
      'enabled': 1,
    });
    await db.insert('subscription', {
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
    await db.insert('rule_version', {
      'group_id': 'sub_1',
      'hash': 'abcd',
      'rule_count': 1,
      'created_at': 1,
      'rules_json': '["||ads.example^"]',
    });
    await db.insert('dns_log', {
      'timestamp': 10,
      'queryName': 'ads.example',
      'queryType': 1,
      'result': 'BLOCKED',
      'cached': 0,
    });
    await db.insert('dns_cache', {
      'key': 'cache-1',
      'queryName': 'ads.example',
      'queryType': 1,
      'queryClass': 1,
      'createdAt': 1,
      'expiresAt': 2,
      'hitCount': 0,
      'originalTtlSeconds': 60,
      'ttlOffsets': '[]',
      'response': Uint8List.fromList(const [1, 2, 3]),
      'responseSize': 3,
    });
    await db.insert('http_request_log', {
      'timestamp': 11,
      'packageName': 'com.example',
      'protocol': 'h2',
      'outcome': 'blocked',
    });
    await db.insert('app_traffic_daily', {
      'date': '2026-11-16',
      'package_name': 'com.example',
      'app_name': '示例',
      'tx_bytes': 1,
      'rx_bytes': 2,
      'updated_at': 1,
    });
    await db.insert('automation_rule', {
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
  }

  Future<void> seedExpress(Database db) async {
    await db.insert('block_rule', {
      'pattern': 'express.example',
      'rawLine': 'express.example',
      'addedAt': 1,
      'enabled': 1,
      'important': 0,
      'appInverted': 0,
      'isWildcard': 0,
      'isRegex': 0,
    });
    await db.insert('dns_log', {
      'timestamp': 12,
      'queryName': 'express.example',
      'queryType': 1,
      'result': 'PASSED',
      'cached': 0,
    });
  }

  Future<void> seedAllLegacy() async {
    final normal = await createLegacy(LegacyStorageSource.normalDatabase, [
      DatabaseKind.normalRules,
      DatabaseKind.normalLogs,
      DatabaseKind.global,
    ]);
    await seedNormal(normal);
    await normal.close();

    final express = await createLegacy(LegacyStorageSource.expressDatabase, [
      DatabaseKind.expressRules,
      DatabaseKind.expressLogs,
    ]);
    await seedExpress(express);
    await express.close();

  }

  Future<int> count(DatabaseKind kind, String table) async {
    final db = await AppDatabase.open(kind.fileName, create: false);
    if (db == null) return -1;
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM `$table`');
      return (rows.first['n'] as num).toInt();
    } finally {
      await db.close();
    }
  }

  test('旧合并库复制到五个新库并保留旧文件', () async {
    await seedAllLegacy();

    final result = await ensureStorageV2(
      store,
      native: const NoopStorageV2Native(),
    );

    expect(result.ready, isTrue, reason: result.error);
    expect(
      LegacySettings(store).storageV2State,
      StorageContract.stateVerified,
    );
    expect(await count(DatabaseKind.normalRules, 'block_rule'), 1);
    expect(await count(DatabaseKind.normalRules, 'subscription'), 1);
    expect(await count(DatabaseKind.normalRules, 'rule_version'), 1);
    expect(await count(DatabaseKind.normalLogs, 'dns_log'), 1);
    expect(await count(DatabaseKind.normalLogs, 'http_request_log'), 1);
    expect(await count(DatabaseKind.normalLogs, 'app_traffic_daily'), 1);
    expect(await count(DatabaseKind.normalLogs, 'dns_cache'), 0);
    expect(await count(DatabaseKind.expressRules, 'block_rule'), 1);
    expect(await count(DatabaseKind.expressLogs, 'dns_log'), 1);
    expect(await count(DatabaseKind.global, 'automation_rule'), 1);
    for (final name in LegacyStorageSource.allOldDatabases.take(2)) {
      expect(File(p.join(directory.path, name)).existsSync(), isTrue);
    }
  });

  test('数据面运行中推迟迁移且不写标记', () async {
    await seedAllLegacy();
    final result = await ensureStorageV2(
      store,
      dataPlaneRunning: true,
      native: const NoopStorageV2Native(),
    );
    expect(result.ready, isFalse);
    expect(result.deferred, isTrue);
    expect(LegacySettings(store).storageV2State, StorageContract.stateIdle);
    expect(
      LegacySettings(store).storageV2Error,
      contains('data plane'),
    );
  });

  test('重复执行不会重复插入', () async {
    await seedAllLegacy();
    await ensureStorageV2(store, native: const NoopStorageV2Native());
    final again = await ensureStorageV2(
      store,
      native: const NoopStorageV2Native(),
    );
    expect(again.ready, isTrue);
    expect(await count(DatabaseKind.normalRules, 'block_rule'), 1);
  });

  test('校验失败时删除新库并保留旧库', () async {
    await seedAllLegacy();
    final result = await ensureStorageV2(
      store,
      native: const _FailingNative(),
    );
    expect(result.ready, isFalse);
    expect(LegacySettings(store).storageV2State, StorageContract.stateIdle);
    expect(
      File(
        p.join(directory.path, LegacyStorageSource.normalDatabase),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(directory.path, DatabaseKind.normalRules.fileName),
      ).existsSync(),
      isFalse,
    );
  });

  test('清理删除旧库、旧偏好键并进入已清理状态', () async {
    await seedAllLegacy();
    await ensureStorageV2(store, native: const NoopStorageV2Native());
    store.putInt(StorageContract.settingsContainer, 'storage_layout_version', 1);

    final result = await cleanupStorageV2(
      store,
      dataPlaneRunning: false,
      native: const NoopStorageV2Native(),
    );

    expect(result.ready, isTrue, reason: result.error);
    expect(LegacySettings(store).storageV2State, StorageContract.stateCleaned);
    for (final name in LegacyStorageSource.allOldDatabases) {
      expect(
        File(p.join(directory.path, name)).existsSync(),
        isFalse,
        reason: name,
      );
    }
    expect(
      store.read(StorageContract.settingsContainer, 'storage_layout_version'),
      isNull,
    );
    expect(await count(DatabaseKind.normalRules, 'block_rule'), 1);
  });

  test('全新安装创建五个空库', () async {
    final result = await ensureStorageV2(
      store,
      native: const NoopStorageV2Native(),
    );
    expect(result.ready, isTrue, reason: result.error);
    for (final kind in DatabaseKind.values) {
      expect(
        File(p.join(directory.path, kind.fileName)).existsSync(),
        isTrue,
        reason: kind.fileName,
      );
    }
    expect(await count(DatabaseKind.normalLogs, 'dns_log'), 0);
  });

  test('全新安装与标记丢失不显示迁移门禁', () async {
    expect(await hasLegacyStores(), isFalse);
    expect(
      storageV2GateRequired(
        state: StorageContract.stateIdle,
        filesReady: false,
        legacyStoresPresent: false,
      ),
      isFalse,
    );

    await ensureStorageV2(store, native: const NoopStorageV2Native());
    LegacySettings(store).setStorageV2State(StorageContract.stateIdle);
    expect(
      storageV2GateRequired(
        state: StorageContract.stateIdle,
        filesReady: await storageV2FilesReady(),
        legacyStoresPresent: await hasLegacyStores(),
      ),
      isFalse,
    );
  });

  test('存在旧库或迁移中断时显示迁移门禁', () async {
    await seedAllLegacy();
    expect(await hasLegacyStores(), isTrue);
    expect(
      storageV2GateRequired(
        state: StorageContract.stateIdle,
        filesReady: false,
        legacyStoresPresent: true,
      ),
      isTrue,
    );
    expect(
      storageV2GateRequired(
        state: StorageContract.stateCopying,
        filesReady: false,
        legacyStoresPresent: true,
      ),
      isTrue,
    );
    expect(
      storageV2GateRequired(
        state: StorageContract.stateVerified,
        filesReady: false,
        legacyStoresPresent: true,
      ),
      isTrue,
    );
  });

  test('旧库损坏时不进入已验证状态', () async {
    final path = p.join(directory.path, LegacyStorageSource.normalDatabase);
    await File(path).writeAsString('not a database');
    final result = await ensureStorageV2(
      store,
      native: const NoopStorageV2Native(),
    );
    expect(result.ready, isFalse);
    expect(LegacySettings(store).storageV2State, StorageContract.stateIdle);
    expect(File(path).existsSync(), isTrue);
  });

  test('放弃旧数据创建空库', () async {
    await seedAllLegacy();
    final result = await discardStorageV2(
      store,
      native: const NoopStorageV2Native(),
    );
    expect(result.ready, isTrue, reason: result.error);
    expect(await count(DatabaseKind.normalRules, 'block_rule'), 0);
    expect(await count(DatabaseKind.global, 'automation_rule'), 0);
  });
}

class _FailingNative extends NoopStorageV2Native {
  const _FailingNative();

  @override
  Future<Map<String, Object?>> verifyDatabases({
    required List<String> logDatabases,
    required List<String> ruleDatabases,
  }) async => const {'ok': false};
}
