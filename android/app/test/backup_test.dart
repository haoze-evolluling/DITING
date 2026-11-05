// Pins the backup round trip: export parses, import merges into a different
// store and reports what it did.

import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/backup/backup_exporter.dart';
import 'package:diting_android/data/backup/backup_importer.dart';
import 'package:diting_android/data/backup/backup_models.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/db/legacy_schema.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('导出与导入', _backupTransfer);
}

void _backupTransfer() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  /// The minimum rule/subscription schema the exporter and importer touch.
  Future<void> createSchema(Database database) async {
    Future<void> ruleTables(String name, {String? extra}) async {
      await database.execute(
        'CREATE TABLE $name (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'pattern TEXT NOT NULL, rawLine TEXT NOT NULL, addedAt INTEGER NOT NULL, '
        'enabled INTEGER NOT NULL DEFAULT 1, groupName TEXT, important INTEGER '
        'NOT NULL DEFAULT 0, appScope TEXT, appInverted INTEGER NOT NULL DEFAULT 0, '
        'isWildcard INTEGER NOT NULL DEFAULT 0, denyallow TEXT, isRegex INTEGER '
        'NOT NULL DEFAULT 0, dnsType TEXT'
        '${extra == null ? '' : ', $extra'})',
      );
      await database.execute(
        'CREATE TABLE ${name}_source (ruleId INTEGER NOT NULL, '
        'source TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1)',
      );
    }

    await ruleTables('block_rule');
    await ruleTables('allow_rule');
    await ruleTables(
      'rewrite_rule',
      extra: 'targetType TEXT NOT NULL, targetValue TEXT NOT NULL',
    );
    await ruleTables('go_url_rule', extra: "kind TEXT NOT NULL");
    await database.execute(
      'CREATE TABLE subscription (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'url TEXT NOT NULL, name TEXT NOT NULL, sourceType TEXT NOT NULL DEFAULT '
      "'remote', kind TEXT NOT NULL DEFAULT 'domain', enabled INTEGER NOT NULL "
      'DEFAULT 1, ruleCount INTEGER NOT NULL DEFAULT 0, lastUpdated INTEGER NOT '
      'NULL DEFAULT 0, addedAt INTEGER NOT NULL DEFAULT 0, importState TEXT NOT '
      "NULL DEFAULT 'ready', importError TEXT, httpEtag TEXT, "
      'httpLastModified TEXT, ruleSetHash TEXT, lastAttemptAt INTEGER NOT NULL '
      'DEFAULT 0, consecutiveFailureCount INTEGER NOT NULL DEFAULT 0, '
      'mirrorTemplate TEXT, mirrorFallback INTEGER NOT NULL DEFAULT 1, '
      'groupId INTEGER)',
    );
    await database.execute(
      'CREATE TABLE subscription_group (id INTEGER PRIMARY KEY AUTOINCREMENT NOT '
      'NULL, name TEXT NOT NULL, autoUpdateEnabled INTEGER NOT NULL DEFAULT 1, '
      'addedAt INTEGER NOT NULL DEFAULT 0)',
    );
  }

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await createSchema(db);
  });

  tearDown(() => db.close());

  /// A store pre-populated the way an upgrading user's would look.
  MemoryLegacyPrefsStore seededStore() => MemoryLegacyPrefsStore({
    LegacySettings.uiContainer: {
      'app_theme_mode': 'dark',
      'theme_color_style': 'indigo',
      'log_retention_days': 14,
      'dns_log_mode': 'blockedAndErrors',
      'bypass_lan_enabled': false,
      'blocked_app_packages': <String>['com.blocked.one'],
      'blocked_apps_enabled': true,
      'excluded_app_packages': <String>['com.excluded.one'],
      'http_inspection_enabled': true,
      'http_inspection_app_packages': <String>['com.inspect.one'],
      'app_allowlist_rules_json': '{"com.allow.one":["a.test","b.test"]}',
      'app_allowlist_enabled': true,
      'custom_background_enabled': true,
    },
    LegacySettings.expressContainer: {},
  });

  BackupExportSource exportSource(MemoryLegacyPrefsStore store) =>
      BackupExportSource(settings: LegacySettings(store), database: db);

  group('导出', () {
    test('出站代理不含账号密码', () async {
      final store = seededStore();
      store.putString(
        LegacySettings.uiContainer,
        'outbound_proxy_host',
        'h.test',
      );
      store.putString(
        LegacySettings.uiContainer,
        'outbound_proxy_username',
        'u',
      );
      store.putString(
        LegacySettings.uiContainer,
        'outbound_proxy_password',
        'p',
      );
      final result = await const BackupExporter().export(
        exportSource(store),
        groups: {BackupGroup.outbound},
      );

      expect(result.content, contains('h.test'));
      expect(result.content, isNot(contains('outbound_proxy_password')));
      expect(result.content, isNot(contains('outbound_proxy_username')));
      expect(result.content, contains('credentialsExcluded'));
    });

    test('规则只导用户自定义的，不含预设与订阅来源', () async {
      await db.insert('block_rule', {
        'pattern': 'user.test',
        'rawLine': 'user.test',
        'addedAt': 1,
      });
      await db.insert('block_rule_source', {'ruleId': 1, 'source': 'useradd'});
      await db.insert('block_rule', {
        'pattern': 'preset.test',
        'rawLine': 'preset.test',
        'addedAt': 1,
      });
      await db.insert('block_rule_source', {'ruleId': 2, 'source': 'preset'});

      final result = await const BackupExporter().export(
        BackupExportSource(
          settings: LegacySettings(seededStore()),
          database: db,
        ),
        groups: {BackupGroup.domainRules},
      );
      final data =
          (jsonDecode(result.content) as Map<String, Object?>)['data']
              as Map<String, Object?>;
      final rules = data['domainRules'] as List;

      expect(rules, hasLength(1));
      expect((rules.single as Map)['pattern'], 'user.test');
    });

    test('文档只有 format / version / exportedAt / data / selection', () async {
      final export = await const BackupExporter().export(
        exportSource(seededStore()),
        groups: {BackupGroup.blocked, BackupGroup.domainRules},
      );
      final root = jsonDecode(export.content) as Map<String, Object?>;

      // The 1.4.3 flat root (`formatVersion`, `customBlockRules`, `excludedApps`, ...) is gone:
      // everything lives under `data`.
      expect(
        root.keys,
        unorderedEquals([
          'format',
          'version',
          'exportedAt',
          'data',
          'selection',
        ]),
      );
      expect(root['format'], BackupFormat.magic);
      expect(root['version'], BackupFormat.version);
      // Groups are written in [BackupGroup] declaration order, whatever order the caller passed.
      expect(root['selection'], ['domainRules', 'blocked']);
      expect(
        (root['data'] as Map).keys,
        unorderedEquals(['domainRules', 'blocked']),
      );
    });
  });

  group('导入', () {
    Future<BackupImportResult> roundTrip(
      Set<BackupGroup> groups, {
      MemoryLegacyPrefsStore? into,
    }) async {
      final export = await const BackupExporter().export(
        exportSource(seededStore()),
        groups: groups,
      );
      return const BackupImporter().import(
        export.content,
        BackupImportTarget(
          store: into ?? MemoryLegacyPrefsStore(),
          database: db,
        ),
        sourceName: 'test.json',
      );
    }

    test('应用名单做并集，不覆盖本机已有项', () async {
      final target = MemoryLegacyPrefsStore({
        LegacySettings.uiContainer: {
          'blocked_app_packages': <String>['com.local.only'],
          'blocked_apps_enabled': false,
        },
      });
      await roundTrip({BackupGroup.blocked}, into: target);
      final settings = LegacySettings(target);
      expect(
        settings.blockedAppPackages,
        containsAll(<String>['com.local.only', 'com.blocked.one']),
      );
      expect(settings.blockedAppsEnabled, isTrue);
    });

    test('HTTPS 抓包开关不从备份打开（依赖本机是否装了 CA）', () async {
      final target = MemoryLegacyPrefsStore();
      await roundTrip({BackupGroup.httpInspection}, into: target);
      final settings = LegacySettings(target);
      expect(settings.httpInspectionPackages, contains('com.inspect.one'));
      expect(settings.httpInspectionEnabled, isFalse);
    });

    test('同名规则第二次导入被跳过', () async {
      await db.insert('block_rule', {
        'pattern': 'dup.test',
        'rawLine': 'dup.test',
        'addedAt': 1,
      });
      await db.insert('block_rule_source', {'ruleId': 1, 'source': 'useradd'});
      final export = await const BackupExporter().export(
        exportSource(seededStore()),
        groups: {BackupGroup.domainRules},
      );
      final first = await const BackupImporter().import(
        export.content,
        BackupImportTarget(store: MemoryLegacyPrefsStore(), database: db),
      );
      expect(first.added, 0);
      expect(first.skipped, 1);
      expect(await db.query('block_rule'), hasLength(1));
    });

    test('覆写规则同 pattern 不同目标值被更新而不是重复插入', () async {
      await db.insert('rewrite_rule', {
        'pattern': 'r.test',
        'rawLine': 'r.test 1.1.1.1',
        'addedAt': 1,
        'targetType': 'IPv4',
        'targetValue': '1.1.1.1',
      });
      await db.insert('rewrite_rule_source', {
        'ruleId': 1,
        'source': 'useradd',
      });
      final export = await const BackupExporter().export(
        exportSource(seededStore()),
        groups: {BackupGroup.rewriteDomain},
      );
      // Local value changed; import must write the backup's value back.
      await db.update('rewrite_rule', {
        'targetValue': '9.9.9.9',
      }, where: 'id = 1');

      final result = await const BackupImporter().import(
        export.content,
        BackupImportTarget(store: MemoryLegacyPrefsStore(), database: db),
      );
      expect(result.updated, 1);
      final rows = await db.query('rewrite_rule');
      expect(rows, hasLength(1));
      expect(rows.single['targetValue'], '1.1.1.1');
    });

    test('订阅按 (url, kind) 去重，导入后规则数归零要求重新下载', () async {
      await db.insert('subscription', {
        'url': 'https://sub.test/list.txt',
        'name': '订阅A',
        'kind': 'domain',
        'ruleCount': 42,
        'lastUpdated': 123,
        'addedAt': 1,
        'httpEtag': '"etag"',
      });
      final export = await const BackupExporter().export(
        exportSource(seededStore()),
        groups: {BackupGroup.subscriptions},
      );
      await db.delete('subscription');

      final result = await const BackupImporter().import(
        export.content,
        BackupImportTarget(store: MemoryLegacyPrefsStore(), database: db),
      );
      expect(result.subscriptionCount, 1);
      final rows = await db.query('subscription');
      expect(rows, hasLength(1));
      // Only the address is imported, so count, timestamp and ETag start empty.
      expect(rows.single['ruleCount'], 0);
      expect(rows.single['lastUpdated'], 0);
      expect(rows.single['httpEtag'], isNull);

      final again = await const BackupImporter().import(
        export.content,
        BackupImportTarget(store: MemoryLegacyPrefsStore(), database: db),
      );
      expect(again.subscriptionCount, 0);
      expect(await db.query('subscription'), hasLength(1));
    });
  });

  group('格式校验', () {
    Future<BackupImportResult> importText(String text) =>
        const BackupImporter().import(
          text,
          BackupImportTarget(store: MemoryLegacyPrefsStore(), database: db),
        );

    test('空文件被拒绝', () async {
      final result = await importText('   ');
      expect(result.failed, isTrue);
      expect(result.fatalError, contains('为空'));
    });

    test('非 JSON 被拒绝', () async {
      final result = await importText('hello');
      expect(result.failed, isTrue);
      expect(result.fatalError, contains('不是合法的 JSON'));
    });

    test('别人的 JSON 被拒绝（不能把任意文件当配置写进库）', () async {
      final result = await importText('{"foo":1}');
      expect(result.failed, isTrue);
      expect(result.fatalError, contains('不是谛听的备份文件'));
    });

    test('更高版本被拒绝并说明原因', () async {
      final result = await importText(
        '{"format":"diting-backup","version":99,"data":{}}',
      );
      expect(result.failed, isTrue);
      expect(result.fatalError, contains('99'));
    });

    test('没有规则库时规则分组如实报错而不是静默成功', () async {
      final export = await const BackupExporter().export(
        exportSource(seededStore()),
        groups: {BackupGroup.domainRules},
      );
      final result = await const BackupImporter().import(
        export.content,
        BackupImportTarget(store: MemoryLegacyPrefsStore(), database: null),
      );
      expect(result.failedGroups, hasLength(1));
      expect(result.failedGroups.single.error, contains('规则库'));
    });

    test('1.4.3 的扁平备份不再被接受', () async {
      final result = await importText(
        '{"formatVersion":10,"customBlockRules":[{"pattern":"a.test"}]}',
      );
      expect(result.failed, isTrue);
      expect(result.fatalError, contains('不是谛听的备份文件'));
    });

    test('分组格式的 version 1 备份仍能导入', () async {
      final result = await importText(
        '{"format":"diting-backup","version":1,"data":'
        '{"blocked":{"enabled":true,"packages":["com.a"]}}}',
      );
      expect(result.failed, isFalse, reason: result.fatalError);
      expect(result.failedGroups, isEmpty);
    });
  });

  group('重复导入', () {
    test('同一份备份连导三次，服务商不再反复报「更新」', () async {
      final store = seededStore();
      store.putString(
        LegacySettings.uiContainer,
        'user_providers_json',
        '[{"id":"user_a","name":"我的 DoH","protocol":"DOH",'
            '"url":"https://dns.test/dns-query","host":"","port":853}]',
      );
      store.putString(
        LegacySettings.uiContainer,
        'selected_provider_id',
        'user_a',
      );
      final export = await const BackupExporter().export(
        BackupExportSource(settings: LegacySettings(store), database: db),
      );
      final into = MemoryLegacyPrefsStore();
      final target = BackupImportTarget(store: into, database: db);

      final first = await const BackupImporter().import(export.content, target);
      expect(first.failed, isFalse, reason: first.fatalError);
      for (var round = 0; round < 2; round++) {
        final again = await const BackupImporter().import(
          export.content,
          target,
        );
        expect(again.failed, isFalse, reason: again.fatalError);
        expect(again.added, 0, reason: '第 ${round + 2} 次导入又新增了内容');
        final providers = again.outcomes.firstWhere(
          (outcome) => outcome.group == BackupGroup.providers,
        );
        expect(providers.updated, 0, reason: '第 ${round + 2} 次导入仍把服务商标成更新');
      }
    });
  });

  group('全新安装', () {
    test('没有旧库时自建 schema，整份备份都能落库', () async {
      // A fresh install has no data set yet; the importer must work against the schema this app
      // creates, not just the minimal tables the round-trip tests use.
      final directory = Directory.systemTemp.createTempSync('diting_backup');
      final path = p.join(directory.path, LegacyDatabase.mainFile);
      final fresh = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: LegacySchema.versionOf(LegacyDatabase.mainFile),
          onCreate: (database, version) async {
            for (final statement in LegacySchema.statementsFor(
              LegacyDatabase.mainFile,
            )) {
              await database.execute(statement);
            }
          },
        ),
      );
      addTearDown(() async {
        await fresh.close();
        directory.deleteSync(recursive: true);
      });

      await fresh.insert('block_rule', {
        'pattern': 'fresh.test',
        'rawLine': 'fresh.test',
        'addedAt': 1,
      });
      await fresh.insert('block_rule_source', {
        'ruleId': 1,
        'source': 'useradd',
      });
      final export = await const BackupExporter().export(
        BackupExportSource(settings: LegacySettings(seededStore()), database: fresh),
      );
      await fresh.delete('block_rule');
      await fresh.delete('block_rule_source');

      final result = await const BackupImporter().import(
        export.content,
        BackupImportTarget(store: MemoryLegacyPrefsStore(), database: fresh),
      );
      expect(result.failed, isFalse, reason: result.fatalError);
      expect(result.failedGroups, isEmpty);
      final rows = await fresh.query('block_rule');
      expect(rows.single['pattern'], 'fresh.test');
    });
  });
}
