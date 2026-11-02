// Pins the 1.4.3 flat backup format in both directions, so an upgrade or a
// downgrade never loses rules or subscriptions.

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
  group('1.4.3 备份兼容', _legacyBackupCompat);
}

void _legacyBackupCompat() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    for (final statement in LegacySchema.statementsFor(
      LegacyDatabase.mainFile,
    )) {
      await db.execute(statement);
    }
  });

  tearDown(() => db.close());

  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  BackupImportTarget target([LegacyPrefsStore? store]) => BackupImportTarget(
    store: store ?? MemoryLegacyPrefsStore(),
    database: db,
  );

  group('1.4.3 → 2.0', () {
    test('旧版平铺备份能被导入，且规则/订阅真的落库', () async {
      final store = MemoryLegacyPrefsStore();
      final result = await const BackupImporter().import(
        fixture('legacy-export-1.4.3.json'),
        target(store),
      );

      expect(result.failed, isFalse, reason: result.fatalError);
      expect(result.legacyFormat, isTrue);
      expect(result.failedGroups, isEmpty);

      final blockRows = await db.query('block_rule');
      expect(blockRows, hasLength(4));
      expect(
        blockRows.where((row) => row['appScope'] == 'com.example.blocked'),
        hasLength(1),
        reason: '只对某个应用生效的规则必须保留 appScope',
      );
      final allowRows = await db.query('allow_rule');
      expect(allowRows, hasLength(4));

      final subscriptions = await db.query('subscription');
      expect(subscriptions, hasLength(3));
      expect(
        subscriptions.map((row) => row['url']),
        contains('https://example.com/ad-domain.txt'),
      );

      final providers = jsonDecode(
        store.read('dns_vpn_prefs', 'user_providers_json')! as String,
      );
      expect(providers, hasLength(2));
      for (final provider in providers as List) {
        expect((provider as Map)['id'], isNotEmpty);
      }
      expect(store.read('dns_vpn_prefs', 'selected_provider_id'), isNotNull);
      expect(store.read('dns_vpn_prefs', 'dns_resolution_mode'), isNotNull);
    });

    test('旧版备份导入两次不产生重复行', () async {
      final store = MemoryLegacyPrefsStore();
      await const BackupImporter().import(
        fixture('legacy-export-1.4.3.json'),
        target(store),
      );
      final second = await const BackupImporter().import(
        fixture('legacy-export-1.4.3.json'),
        target(store),
      );
      expect(second.failed, isFalse);
      expect(await db.query('block_rule'), hasLength(4));
      expect(await db.query('allow_rule'), hasLength(4));
      expect(await db.query('subscription'), hasLength(3));
    });
  });

  group('2.0 → 1.4.3', () {
    test('导出的文件带旧版平铺键，1.4.3 读出来不再是空内容', () async {
      await const BackupImporter().import(
        fixture('legacy-export-1.4.3.json'),
        target(MemoryLegacyPrefsStore()),
      );
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'user_providers_json':
              '[{"id":"user_a","name":"我的 DoH","protocol":"DOH",'
              '"url":"https://dns.example.com/dns-query","host":"","port":853}]',
          'selected_provider_id': 'user_a',
          'dns_resolution_mode': 'parallel_race',
          'race_provider_ids': '["user_a","preset_alidns_dns"]',
        },
      });
      final export = await const BackupExporter().export(
        BackupExportSource(settings: LegacySettings(store), database: db),
      );
      final root = jsonDecode(export.content) as Map<String, Object?>;

      expect(root['format'], BackupFormat.magic);
      expect(root['data'], isA<Map>());

      // 1.4.3's parser reads every top-level key with optString, so one missing key empties the
      // import
      expect(root['formatVersion'], 10);
      expect(root['providers'], hasLength(1));
      expect(root['selectedProvider'], isA<Map>());
      expect(root['resolutionMode'], 'parallel_race');
      expect(root['raceProviderRefs'], hasLength(2));
      expect(root['customBlockRules'], hasLength(4));
      expect(root['customAllowRules'], hasLength(4));
      expect(root['customRewriteCnameRules'], hasLength(1));
      expect(root['subscriptions'], hasLength(3));
      expect(
        (root['subscriptions'] as List).first,
        containsPair('scope', 'dns'),
      );
      expect(root['appearance'], isA<Map>());
      expect(root['systemSettings'], isA<Map>());
      expect(
        (root['systemSettings'] as Map)['logRetentionDays'],
        isA<int>(),
        reason: '1.4.3 用 getInt 读这个键，写成字符串会被静默忽略',
      );
      expect((root['outboundProxy'] as Map)['credentialsOmitted'], isTrue);
      expect(
        (root['outboundProxy'] as Map).containsKey('proxyAppPackage'),
        isTrue,
      );
    });

    test('旧版字段名逐一存在（防回归清单）', () async {
      final export = await const BackupExporter().export(
        BackupExportSource(
          settings: LegacySettings(
            MemoryLegacyPrefsStore({
              'dns_vpn_prefs': {'app_theme_mode': 'dark'},
            }),
          ),
          database: db,
        ),
      );
      final root = jsonDecode(export.content) as Map<String, Object?>;
      const required = [
        'providers',
        'selectedProvider',
        'resolutionMode',
        'presetDnsService',
        'raceTestDomain',
        'homeProviderVisibility',
        'bootstrapEnabled',
        'bootstrapIps',
        'bootstrapPresetIds',
        'dnsCache',
        'outboundProxy',
        'mirrorTemplates',
        'subscriptionGroups',
        'subscriptions',
        'customBlockRules',
        'customAllowRules',
        'customRewriteDomainRules',
        'customRewriteCnameRules',
        'customAddressRules',
        'excludedApps',
        'blockedApps',
        'blockedAppsEnabled',
        'appAllowlistRules',
        'appAllowlistEnabled',
        'httpInspection',
        'domainRulesEnabled',
        'addressRulesEnabled',
        'encryptedDnsBlockingEnabled',
        'blockResponseMode',
        'dynamicBlockResponse',
        'allowEditDefaultWhitelist',
        'subscriptionAutoUpdate',
        'appearance',
        'systemSettings',
      ];
      for (final key in required) {
        expect(root, contains(key), reason: '1.4.3 需要一个顶层键：$key');
      }
    });
  });

  group('全新安装', () {
    test('没有旧库时自建 schema，备份导入不再报没有规则库', () async {
      final path = p.join(
        Directory.systemTemp.createTempSync('diting_schema').path,
        LegacyDatabase.mainFile,
      );
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
        Directory(p.dirname(path)).deleteSync(recursive: true);
      });

      final result = await const BackupImporter().import(
        fixture('legacy-export-1.4.3.json'),
        BackupImportTarget(store: MemoryLegacyPrefsStore(), database: fresh),
      );
      expect(result.failed, isFalse, reason: result.fatalError);
      expect(result.failedGroups, isEmpty);
      expect(await fresh.query('subscription'), hasLength(3));
    });
  });
  group('重复导入', () {
    test('同一份 2.0 备份连导三次，服务商不再反复报「更新」', () async {
      final store = MemoryLegacyPrefsStore();
      final target = BackupImportTarget(store: store, database: db);
      final content = fixture('legacy-export-1.4.3.json');
      final first = await const BackupImporter().import(content, target);
      expect(first.failed, isFalse, reason: first.fatalError);

      for (var round = 0; round < 2; round++) {
        final again = await const BackupImporter().import(content, target);
        final providers = again.outcomes.firstWhere(
          (outcome) => outcome.group == BackupGroup.providers,
        );
        expect(providers.updated, 0, reason: '第 ${round + 2} 次导入仍把服务商标成更新');
        expect(providers.added, 0);
      }
    });

    test('2.0 导出的备份导入回 2.0 也是幂等的', () async {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'app_theme_mode': 'dark',
          'log_retention_days': 7,
          'user_providers_json':
              '[{"id":"user_a","name":"我的 DoH","protocol":"DOH",'
              '"url":"https://dns.example.com/dns-query","host":"","port":853}]',
          'selected_provider_id': 'user_a',
        },
      });
      final export = await const BackupExporter().export(
        BackupExportSource(settings: LegacySettings(store), database: db),
      );
      final empty = MemoryLegacyPrefsStore();
      final first = await const BackupImporter().import(
        export.content,
        target(empty),
      );
      expect(first.failed, isFalse, reason: first.fatalError);
      final second = await const BackupImporter().import(
        export.content,
        target(empty),
      );
      expect(second.failed, isFalse, reason: second.fatalError);
      expect(second.added, 0);
      expect(second.updated, 0);
    });
  });
}
