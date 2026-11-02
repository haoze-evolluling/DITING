// Pins the data-cleanup contract: every action must delete rows, so assertions go
// against the DB.

import 'package:diting_android/data/cleanup/data_cleanup_service.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_shared/data/native/platform_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('数据清理', _dataCleanup);
}

/// Pins the data-cleanup contract: every action must delete rows, so assertions go against the DB
void _dataCleanup() {
  // The native channel is unregistered, so the bridge degrades to 0 as on a non-Android host
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database main;
  late MemoryLegacyPrefsStore prefs;

  const seedVersionCode = 20001;

  Future<void> createSchema(Database db, {bool withRuntime = true}) async {
    if (withRuntime) {
      for (final table in [
        'dns_log',
        'dns_cache',
        'dns_race_log',
        'bootstrap_log',
      ]) {
        await db.execute(
          'CREATE TABLE $table (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
          'timestamp INTEGER)',
        );
      }
      await db.execute(
        'CREATE TABLE app_traffic_daily (date TEXT NOT NULL, '
        'package_name TEXT NOT NULL, tx_bytes INTEGER NOT NULL, '
        'rx_bytes INTEGER NOT NULL, PRIMARY KEY(date, package_name))',
      );
    }
    await db.execute(
      'CREATE TABLE http_request_log (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'timestamp INTEGER, outcome TEXT)',
    );
    for (final table in [
      'block_rule',
      'allow_rule',
      'rewrite_rule',
      'go_url_rule',
      'cosmetic_rule',
    ]) {
      await db.execute(
        'CREATE TABLE $table (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'pattern TEXT, rawLine TEXT, addedAt INTEGER NOT NULL DEFAULT 0, '
        'enabled INTEGER NOT NULL DEFAULT 1, groupName TEXT, important INTEGER '
        'NOT NULL DEFAULT 0, appScope TEXT, appInverted INTEGER NOT NULL DEFAULT 0, '
        'isWildcard INTEGER NOT NULL DEFAULT 0, denyallow TEXT, isRegex INTEGER '
        'NOT NULL DEFAULT 0, dnsType TEXT, targetType TEXT, targetValue TEXT, '
        'domain TEXT, selector TEXT, isException INTEGER NOT NULL DEFAULT 0, '
        'kind TEXT)',
      );
      await db.execute(
        'CREATE TABLE ${table}_source (ruleId INTEGER NOT NULL, '
        'source TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1)',
      );
    }
    await db.execute(
      'CREATE TABLE subscription (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'url TEXT, name TEXT, kind TEXT, ruleCount INTEGER NOT NULL DEFAULT 0, '
      'lastUpdated INTEGER NOT NULL DEFAULT 0, httpEtag TEXT, '
      'httpLastModified TEXT, ruleSetHash TEXT)',
    );
    await db.execute(
      'CREATE TABLE subscription_group (id INTEGER PRIMARY KEY AUTOINCREMENT '
      'NOT NULL, name TEXT)',
    );
    await db.execute(
      'CREATE TABLE subscription_auto_update_item (subscriptionId INTEGER NOT NULL, '
      'status TEXT)',
    );
    await db.execute(
      'CREATE TABLE mirror_template (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'name TEXT)',
    );
  }

  setUp(() async {
    main = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await createSchema(main);
    prefs = MemoryLegacyPrefsStore({
      LegacySettings.uiContainer: {
        'blocked_app_packages': <String>['com.example'],
        'http_inspection_enabled': true,
        'custom_background_uri': 'content://wallpaper/1',
        'initial_agreement_accepted': true,
        'settings_guide_acknowledged_ids': <String>['home'],
      },
      'mode_permission_preferences': {
        'recommendation_dismissed_vpn': true,
        'onboarding_completed_normal': true,
      },
    });
  });

  tearDown(() => main.close());

  DataCleanupService buildService() => DataCleanupService(
    prefs: prefs,
    platform: PlatformBridge(),
    outboundProxy: MemoryOutboundProxyStore(),
    appVersionCode: seedVersionCode,
    openDatabase: (fileName) async =>
        fileName == LegacyDatabase.mainFile ? main : null,
    // The preset whitelist asset is absent: an empty table means skip seeding, not clear all
    loadPresetAsset: () async => '',
  );

  group('运行数据', () {
    test('删除请求日志清空四张日志表', () async {
      for (final table in [
        'dns_log',
        'http_request_log',
        'dns_race_log',
        'bootstrap_log',
      ]) {
        await main.insert(table, {'timestamp': 1});
        await main.insert(table, {'timestamp': 2});
      }
      final result = await buildService().run(CleanupAction.logs);
      expect(result.removed, 8);
      for (final table in [
        'dns_log',
        'http_request_log',
        'dns_race_log',
        'bootstrap_log',
      ]) {
        expect(await main.query(table), isEmpty, reason: table);
      }
    });

    test('删除流量统计只清 app_traffic_daily', () async {
      await main.insert('app_traffic_daily', {
        'date': '2026-10-22',
        'package_name': 'com.example',
        'tx_bytes': 1,
        'rx_bytes': 2,
      });
      await main.insert('dns_log', {'timestamp': 1});
      final result = await buildService().run(CleanupAction.traffic);
      expect(result.removed, 1);
      expect(await main.query('app_traffic_daily'), isEmpty);
      expect(await main.query('dns_log'), hasLength(1));
    });

    test('删除 DNS 缓存只清 dns_cache', () async {
      await main.insert('dns_cache', {'timestamp': 1});
      final result = await buildService().run(CleanupAction.dnsCache);
      expect(result.removed, 1);
      expect(await main.query('dns_cache'), isEmpty);
    });
  });

  group('权重数据', () {
    test('两个权重键在三个数据集容器里都被删', () async {
      for (final container in [
        LegacySettings.uiContainer,
        LegacySettings.expressContainer,
        LegacySettings.serverContainer,
      ]) {
        prefs.putString(container, 'provider_health_json', '{}');
        prefs.putString(container, 'bootstrap_health_json', '{}');
      }
      final service = buildService();
      expect((await service.run(CleanupAction.providerWeights)).removed, 3);
      expect((await service.run(CleanupAction.bootstrapWeights)).removed, 3);
      for (final container in [
        LegacySettings.uiContainer,
        LegacySettings.expressContainer,
        LegacySettings.serverContainer,
      ]) {
        expect(prefs.read(container, 'provider_health_json'), isNull);
        expect(prefs.read(container, 'bootstrap_health_json'), isNull);
      }
    });

    test('没有权重样本时如实报 0 项而不是「已删除」', () async {
      final result = await buildService().run(CleanupAction.providerWeights);
      expect(result.removed, 0);
      expect(result.message, contains('没有可清理的数据'));
    });
  });

  group('规则与订阅', () {
    test('删除全部域名规则清四类表并保留地址规则', () async {
      for (final table in ['block_rule', 'allow_rule', 'cosmetic_rule']) {
        await main.insert(table, {'pattern': 'a.com'});
        await main.insert('${table}_source', {
          'ruleId': 1,
          'source': 'useradd',
        });
      }
      await main.insert('rewrite_rule', {
        'pattern': 'b.com',
        'targetType': 'IPv4',
      });
      await main.insert('rewrite_rule_source', {
        'ruleId': 1,
        'source': 'useradd',
      });
      await main.insert('rewrite_rule', {
        'pattern': 'c.com',
        'targetType': 'CNAME',
      });
      await main.insert('rewrite_rule_source', {
        'ruleId': 2,
        'source': 'useradd',
      });
      await main.insert('go_url_rule', {'pattern': 'https://x.test'});

      final result = await buildService().run(CleanupAction.domainRules);
      expect(result.removed, greaterThan(0));
      for (final table in ['block_rule', 'allow_rule', 'cosmetic_rule']) {
        expect(await main.query(table), isEmpty, reason: table);
      }
      final rewrites = await main.query('rewrite_rule');
      expect(rewrites, hasLength(1));
      expect(rewrites.single['targetType'], 'CNAME');
      expect(await main.query('go_url_rule'), hasLength(1));
    });

    test('删除全部地址规则只清 CNAME 与 go_url_rule', () async {
      await main.insert('rewrite_rule', {
        'pattern': 'b.com',
        'targetType': 'IPv4',
      });
      await main.insert('rewrite_rule', {
        'pattern': 'c.com',
        'targetType': 'CNAME',
      });
      await main.insert('go_url_rule', {'pattern': 'https://x.test'});
      await main.insert('block_rule', {'pattern': 'a.com'});

      await buildService().run(CleanupAction.addressRules);
      final rewrites = await main.query('rewrite_rule');
      expect(rewrites, hasLength(1));
      expect(rewrites.single['targetType'], 'IPv4');
      expect(await main.query('go_url_rule'), isEmpty);
      expect(await main.query('block_rule'), hasLength(1));
    });

    test('删除订阅清订阅行、分组、自动更新任务与订阅来源的规则', () async {
      await main.insert('subscription', {
        'url': 'https://s.test',
        'kind': 'domain',
      });
      await main.insert('subscription_group', {'name': 'g'});
      await main.insert('subscription_auto_update_item', {
        'subscriptionId': 1,
        'status': 'success',
      });
      await main.insert('block_rule', {'pattern': 'ads.test'});
      await main.insert('block_rule_source', {'ruleId': 1, 'source': 'sub_1'});
      await main.insert('block_rule', {'pattern': 'mine.test'});
      await main.insert('block_rule_source', {
        'ruleId': 2,
        'source': 'useradd',
      });

      await buildService().run(CleanupAction.subscriptions);
      expect(await main.query('subscription'), isEmpty);
      expect(await main.query('subscription_group'), isEmpty);
      expect(await main.query('subscription_auto_update_item'), isEmpty);
      final rules = await main.query('block_rule');
      expect(rules, hasLength(1));
      expect(rules.single['pattern'], 'mine.test');
    });
  });

  group('应用与存储', () {
    test('重置应用控制名单清四份名单与抓包就绪标记', () async {
      prefs.putString(
        LegacySettings.uiContainer,
        'app_allowlist_rules_json',
        '{}',
      );
      prefs.putBool(LegacySettings.uiContainer, 'https_inspection_ready', true);
      prefs.putBool(
        LegacySettings.uiContainer,
        'custom_background_enabled',
        true,
      );
      final result = await buildService().run(CleanupAction.appRules);
      expect(result.removed, greaterThan(0));
      for (final key in [
        'blocked_app_packages',
        'http_inspection_enabled',
        'app_allowlist_rules_json',
      ]) {
        expect(
          prefs.read(LegacySettings.uiContainer, key),
          isNull,
          reason: key,
        );
      }
      expect(
        prefs.read(LegacySettings.uiContainer, 'custom_background_enabled'),
        isNotNull,
      );
    });
  });

  group('全面清理', () {
    test('按序清完全部清单并累计条数', () async {
      await main.insert('dns_log', {'timestamp': 1});
      await main.insert('app_traffic_daily', {
        'date': '2026-10-22',
        'package_name': 'com.example',
        'tx_bytes': 1,
        'rx_bytes': 2,
      });
      await main.insert('block_rule', {'pattern': 'a.com'});
      await main.insert('mirror_template', {'name': 'm'});

      final result = await buildService().run(CleanupAction.allData);
      expect(result.removed, greaterThan(0));
      expect(await main.query('dns_log'), isEmpty);
      expect(await main.query('app_traffic_daily'), isEmpty);
      expect(await main.query('mirror_template'), isEmpty);
      expect(
        prefs.read(LegacySettings.uiContainer, 'initial_agreement_accepted'),
        isNull,
      );
    });
  });

  group('降级', () {
    test('没有数据库文件时不抛异常，如实报 0 项', () async {
      final service = DataCleanupService(
        prefs: MemoryLegacyPrefsStore(),
        platform: PlatformBridge(),
        outboundProxy: MemoryOutboundProxyStore(),
        appVersionCode: seedVersionCode,
        openDatabase: (fileName) async => null,
        loadPresetAsset: () async => '',
      );
      final result = await service.run(CleanupAction.logs);
      expect(result.removed, 0);
      expect(result.failed, isFalse);
    });
  });
}
