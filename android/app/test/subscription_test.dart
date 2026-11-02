// Runs the subscription SQL against the real 1.4.3 tables: `ORDER BY`,
// conflicts, cascades.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _zh = lookupAppL10n(const Locale('zh'));

void main() {
  group('订阅表 SQL', _subscriptionRepository);
}

void _subscriptionRepository() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SubscriptionRepository repository;
  var writeCount = 0;

  setUp(() async {
    writeCount = 0;
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE subscription ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'url TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'sourceType TEXT NOT NULL, '
      'kind TEXT NOT NULL, '
      'enabled INTEGER NOT NULL, '
      'ruleCount INTEGER NOT NULL, '
      'lastUpdated INTEGER NOT NULL, '
      'addedAt INTEGER NOT NULL, '
      'importState TEXT NOT NULL, '
      'importError TEXT, '
      'httpEtag TEXT, '
      'httpLastModified TEXT, '
      'ruleSetHash TEXT, '
      'lastAttemptAt INTEGER NOT NULL, '
      'consecutiveFailureCount INTEGER NOT NULL, '
      'mirrorTemplate TEXT, '
      'mirrorFallback INTEGER NOT NULL, '
      'groupId INTEGER)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX index_subscription_url_kind '
      'ON subscription (url, kind)',
    );
    await db.execute(
      'CREATE INDEX index_subscription_groupId ON subscription (groupId)',
    );
    await db.execute(
      'CREATE TABLE subscription_group ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'name TEXT NOT NULL, '
      'autoUpdateEnabled INTEGER NOT NULL, '
      'addedAt INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX index_subscription_group_name '
      'ON subscription_group (name)',
    );
    await db.execute(
      'CREATE TABLE subscription_auto_update_item ('
      'batchId TEXT NOT NULL, '
      'subscriptionId INTEGER NOT NULL, '
      'status TEXT NOT NULL, '
      'changed INTEGER NOT NULL, '
      'ruleCount INTEGER NOT NULL, '
      'PRIMARY KEY (batchId, subscriptionId), '
      'FOREIGN KEY (subscriptionId) REFERENCES subscription (id) '
      'ON DELETE CASCADE)',
    );
    await db.execute('PRAGMA foreign_keys = ON');
    repository = SubscriptionRepository(db, onChanged: () => writeCount++);
  });

  tearDown(() => db.close());

  Future<int> insertSub({
    String url = 'https://example.com/rules.txt',
    String name = '示例订阅',
    SubscriptionKind kind = SubscriptionKind.domain,
    SubscriptionSourceType sourceType = SubscriptionSourceType.remote,
    bool enabled = true,
    int addedAt = 1000,
    int? groupId,
    SubscriptionImportState state = SubscriptionImportState.ready,
    String? etag,
    String? lastModified,
    int failureCount = 0,
  }) => repository.insert(
    SubscriptionRecord(
      id: 0,
      url: url,
      name: name,
      sourceType: sourceType,
      kind: kind,
      enabled: enabled,
      ruleCount: 0,
      lastUpdated: 0,
      addedAt: addedAt,
      importState: state,
      lastAttemptAt: 0,
      consecutiveFailureCount: failureCount,
      httpEtag: etag,
      httpLastModified: lastModified,
      mirrorFallback: true,
      groupId: groupId,
    ),
  );

  group('查询', () {
    test('all() 按 addedAt DESC', () async {
      await insertSub(url: 'https://a', addedAt: 100, name: 'A');
      await insertSub(url: 'https://b', addedAt: 300, name: 'B');
      await insertSub(url: 'https://c', addedAt: 200, name: 'C');

      expect((await repository.all()).map((record) => record.name), [
        'B',
        'C',
        'A',
      ]);
    });

    test('kind / sourceType 过滤与 kind 归一化', () async {
      await insertSub(url: 'https://domain', kind: SubscriptionKind.domain);
      await insertSub(url: 'https://hosts', kind: SubscriptionKind.hosts);
      await insertSub(
        url: 'file:///local.txt',
        sourceType: SubscriptionSourceType.local,
        kind: SubscriptionKind.hosts,
      );

      expect(await repository.byKind(SubscriptionKind.hosts), hasLength(2));
      expect(
        await repository.remoteByKind(SubscriptionKind.hosts),
        hasLength(1),
      );
      expect(await repository.allRemote(), hasLength(2));
      expect(SubscriptionKind.normalize('HOSTS'), SubscriptionKind.hosts);
      expect(SubscriptionKind.normalize(null), SubscriptionKind.domain);
      expect(SubscriptionKind.isCanonical('domain'), isTrue);
      expect(SubscriptionKind.isCanonical('weird'), isFalse);
    });

    test('groups() 按 addedAt ASC, name NOCASE ASC', () async {
      await db.insert('subscription_group', {
        'name': 'beta',
        'autoUpdateEnabled': 1,
        'addedAt': 100,
      });
      await db.insert('subscription_group', {
        'name': 'Alpha',
        'autoUpdateEnabled': 1,
        'addedAt': 100,
      });
      await db.insert('subscription_group', {
        'name': 'zeta',
        'autoUpdateEnabled': 1,
        'addedAt': 50,
      });

      expect((await repository.groups()).map((group) => group.name), [
        'zeta',
        'Alpha',
        'beta',
      ]);
    });

    test('allAutoUpdatableRemote：启用 + 无分组或分组开启', () async {
      final openGroup = await repository.insertGroup(name: '开启组');
      final closedGroup = await repository.insertGroup(
        name: '关闭组',
        autoUpdateEnabled: false,
      );
      await insertSub(url: 'https://nogroup', addedAt: 1);
      await insertSub(url: 'https://open', addedAt: 2, groupId: openGroup);
      await insertSub(url: 'https://closed', addedAt: 3, groupId: closedGroup);
      await insertSub(url: 'https://disabled', addedAt: 4, enabled: false);
      await insertSub(
        url: 'https://local',
        addedAt: 5,
        sourceType: SubscriptionSourceType.local,
      );

      expect(
        (await repository.allAutoUpdatableRemote()).map(
          (record) => Uri.parse(record.url).host,
        ),
        ['open', 'nogroup'],
      );
    });
  });

  group('唯一性', () {
    test('(url, kind) 冲突返回已存在行 id，不新增行', () async {
      final first = await insertSub(url: 'https://dup', name: '原始');
      final second = await insertSub(url: 'https://dup', name: '重复');

      expect(second, first);
      final rows = await db.query('subscription');
      expect(rows, hasLength(1));
      expect(rows.single['name'], '原始');
      expect(writeCount, 1);
    });
  });

  group('级联与外键', () {
    test('删除订阅后 auto_update_item 级联删除', () async {
      final id = await insertSub();
      await db.insert('subscription_auto_update_item', {
        'batchId': 'batch-1',
        'subscriptionId': id,
        'status': 'success',
        'changed': 1,
        'ruleCount': 42,
      });
      expect(await repository.autoUpdateItems('batch-1'), hasLength(1));

      await repository.deleteById(id);

      expect(await db.query('subscription_auto_update_item'), isEmpty);
    });
  });

  group('更新路径', () {
    test('consecutiveFailureCount 累加而不是置 1', () async {
      final id = await insertSub();
      await repository.markUpdateFailed(id, error: 'HTTP 500', attemptedAt: 10);
      await repository.markUpdateFailed(id, error: 'HTTP 500', attemptedAt: 20);
      await repository.markUpdateFailed(id, error: 'HTTP 500', attemptedAt: 30);

      final record = (await repository.byId(id))!;
      expect(record.consecutiveFailureCount, 3);
      expect(record.importState, SubscriptionImportState.failed);
      expect(record.importError, 'HTTP 500');
      expect(record.lastAttemptAt, 30);
    });

    test('markImported 清零失败计数并写回校验符', () async {
      final id = await insertSub(failureCount: 4);
      await repository.markImported(
        id,
        ruleCount: 1200,
        lastUpdated: 5000,
        etag: '"abc"',
        lastModified: 'Wed, 21 Oct 2015 07:28:00 GMT',
      );

      final record = (await repository.byId(id))!;
      expect(record.ruleCount, 1200);
      expect(record.lastUpdated, 5000);
      expect(record.importState, SubscriptionImportState.ready);
      expect(record.importError, isNull);
      expect(record.consecutiveFailureCount, 0);
      expect(record.httpEtag, '"abc"');
      expect(record.httpLastModified, 'Wed, 21 Oct 2015 07:28:00 GMT');
      expect(record.lastAttemptAt, 5000);
      expect(record.ruleSetHash, isNull);
    });

    test('updateConfig 改写可编辑列，换源时清空校验符', () async {
      final id = await insertSub(etag: '"e"', lastModified: 'lm');
      await repository.updateConfig(
        id,
        name: '新名',
        url: 'https://example.com/hosts.txt',
        kind: SubscriptionKind.hosts,
        groupId: null,
        mirrorTemplate: 'https://m/{url}',
        mirrorFallback: false,
        resetValidators: true,
      );

      final record = (await repository.byId(id))!;
      expect(record.name, '新名');
      expect(record.url, 'https://example.com/hosts.txt');
      expect(record.kind, SubscriptionKind.hosts);
      expect(record.mirrorTemplate, 'https://m/{url}');
      expect(record.mirrorFallback, isFalse);
      expect(record.httpEtag, isNull);
      expect(record.httpLastModified, isNull);
    });

    test('每次写都触发 onChanged（revision 自增）', () async {
      final id = await insertSub();
      final afterInsert = writeCount;
      await repository.setEnabled(id, false);
      await repository.setName(id, '改名');
      await repository.setImportState(id, SubscriptionImportState.importing);
      await repository.markUpdateFailed(id, error: 'x', attemptedAt: 1);
      await repository.markNotModified(id, attemptedAt: 2);
      await repository.resetAfterRuleCleanup();
      await repository.deleteById(id);

      expect(afterInsert, 1);
      expect(writeCount, afterInsert + 7);
    });
  });

  group('模型解析容错', () {
    test('fromRow 缺列不抛错，布尔按 INTEGER 解读', () {
      final record = SubscriptionRecord.fromRow(const {});

      expect(record.id, 0);
      expect(record.url, '');
      expect(record.enabled, isTrue);
      expect(record.mirrorFallback, isTrue);
      expect(record.kind, SubscriptionKind.domain);
      expect(record.sourceType, SubscriptionSourceType.remote);
      expect(record.importState, SubscriptionImportState.ready);
      expect(record.groupId, isNull);
    });

    test('枚举 storageValue 与 1.4.3 常量逐字一致', () {
      expect(SubscriptionSourceType.remote.storageValue, 'remote');
      expect(SubscriptionSourceType.local.storageValue, 'local');
      expect(SubscriptionKind.domain.storageValue, 'domain');
      expect(SubscriptionKind.hosts.storageValue, 'hosts');
      expect(SubscriptionImportState.ready.storageValue, 'ready');
      expect(SubscriptionImportState.importing.storageValue, 'importing');
      expect(SubscriptionImportState.failed.storageValue, 'failed');
      expect(
        SubscriptionAutoUpdateStatus.pendingRetry.storageValue,
        'pending_retry',
      );
      expect(SubscriptionAutoUpdateStatus.success.storageValue, 'success');
      expect(SubscriptionAutoUpdateStatus.failed.storageValue, 'failed');
      expect(SubscriptionKind.domain.displayName(_zh), '黑白名单规则');
      expect(SubscriptionKind.hosts.displayName(_zh), 'hosts 规则');
    });
  });
}
