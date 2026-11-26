import 'package:diting_android/data/cleanup/cleanup_plan.dart';
import 'package:diting_android/data/cleanup/data_cleanup_service.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_android/data/native/runtime_log_bridge.dart';
import 'package:diting_android/data/native/platform_bridge.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('数据清理', _dataCleanup);
}

void _dataCleanup() {
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
      'httpLastModified TEXT, ruleSetHash TEXT, mirrorTemplate TEXT)',
    );
    await db.execute(
      'CREATE TABLE rule_version (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'group_id TEXT NOT NULL, hash TEXT NOT NULL, rule_count INTEGER NOT NULL, '
      'created_at INTEGER NOT NULL, rules_json TEXT NOT NULL)',
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
    await db.execute(
      'CREATE TABLE automation_rule (id TEXT PRIMARY KEY NOT NULL, name TEXT)',
    );
    await db.execute(
      'CREATE TABLE automation_profile (id TEXT PRIMARY KEY NOT NULL, name TEXT)',
    );
    await db.execute(
      'CREATE TABLE automation_event (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'ts INTEGER NOT NULL, event TEXT NOT NULL)',
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

  tearDown(() async {
    _clearMock(runtimeLogChannelName);
    _clearMock('com.haoze.diting/recognition');
    await main.close();
  });

  DataCleanupService buildService() => DataCleanupService(
    prefs: prefs,
    platform: PlatformBridge(),
    outboundProxy: MemoryOutboundProxyStore(),
    appVersionCode: seedVersionCode,
    openDatabase: (fileName) async => main,
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

    test('删除运行日志文件走运行日志通道', () async {
      _mockChannel(runtimeLogChannelName, (call) async {
        expect(call.method, 'clear');
        return 3;
      });
      final result = await buildService().run(CleanupAction.runtimeLogs);
      expect(result.removed, 3);
      expect(result.failed, isFalse);
    });

    test('没有运行日志通道时降级为 0 项', () async {
      final result = await buildService().run(CleanupAction.runtimeLogs);
      expect(result.removed, 0);
      expect(result.failed, isFalse);
    });

    test('删除自动化执行记录只清 automation_event', () async {
      await main.insert('automation_event', {'ts': 1, 'event': 'run'});
      await main.insert('automation_rule', {'id': 'r1', 'name': 'n'});
      final result = await buildService().run(CleanupAction.automationEvents);
      expect(result.removed, 1);
      expect(await main.query('automation_event'), isEmpty);
      expect(await main.query('automation_rule'), hasLength(1));
    });
  });

  group('权重数据', () {
    test('两个权重键在两个数据集容器里都被删', () async {
      for (final container in [
        LegacySettings.uiContainer,
        LegacySettings.expressContainer,
      ]) {
        prefs.putString(container, 'provider_health_json', '{}');
        prefs.putString(container, 'bootstrap_health_json', '{}');
      }
      final service = buildService();
      expect((await service.run(CleanupAction.providerWeights)).removed, 2);
      expect((await service.run(CleanupAction.bootstrapWeights)).removed, 2);
      for (final container in [
        LegacySettings.uiContainer,
        LegacySettings.expressContainer,
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
      await main.insert('rule_version', {
        'group_id': 'sub_1',
        'hash': 'h',
        'rule_count': 1,
        'created_at': 1,
        'rules_json': '[]',
      });

      await buildService().run(CleanupAction.subscriptions);
      expect(await main.query('subscription'), isEmpty);
      expect(await main.query('subscription_group'), isEmpty);
      expect(await main.query('subscription_auto_update_item'), isEmpty);
      expect(await main.query('rule_version'), isEmpty);
      final rules = await main.query('block_rule');
      expect(rules, hasLength(1));
      expect(rules.single['pattern'], 'mine.test');
    });

    test('删除规则版本快照只清 rule_version', () async {
      await main.insert('rule_version', {
        'group_id': 'sub_1',
        'hash': 'h',
        'rule_count': 1,
        'created_at': 1,
        'rules_json': '[]',
      });
      await main.insert('mirror_template', {'name': 'keep'});
      final result = await buildService().run(CleanupAction.ruleVersions);
      expect(result.removed, 1);
      expect(await main.query('rule_version'), isEmpty);
      expect(await main.query('mirror_template'), hasLength(1));
    });

    test('删除自定义镜像模板并解除镜像引用', () async {
      await main.insert('mirror_template', {'name': 'mirror-a'});
      await main.insert('subscription', {
        'url': 'https://s.test',
        'kind': 'domain',
        'mirrorTemplate': 'https://mirror/{url}',
      });
      prefs.putBool(LegacySettings.uiContainer, 'global_mirror_enabled', true);
      prefs.putString(
        LegacySettings.uiContainer,
        'global_mirror_template',
        'https://global/{url}',
      );
      final result = await buildService().run(CleanupAction.mirrorTemplates);
      expect(result.removed, greaterThan(0));
      expect(await main.query('mirror_template'), isEmpty);
      final subscriptions = await main.query('subscription');
      expect(subscriptions.single['mirrorTemplate'], isNull);
      expect(
        prefs.read(LegacySettings.uiContainer, 'global_mirror_enabled'),
        isNull,
      );
      expect(
        prefs.read(LegacySettings.uiContainer, 'global_mirror_template'),
        isNull,
      );
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

    test('删除识别成员缓存清三个键与头像缓存', () async {
      const container = 'recognition_members';
      prefs.putString(container, 'config_json', '{}');
      prefs.putLong(container, 'saved_at_ms', 1);
      prefs.putString(container, 'etag', 'abc');
      _mockChannel('com.haoze.diting/recognition', (call) async {
        expect(call.method, 'clear');
        return 2;
      });
      final result = await buildService().run(CleanupAction.recognitionMembers);
      expect(result.removed, 5);
      for (final key in ['config_json', 'saved_at_ms', 'etag']) {
        expect(prefs.read(container, key), isNull, reason: key);
      }
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
      await main.insert('rule_version', {
        'group_id': 'sub_1',
        'hash': 'h',
        'rule_count': 1,
        'created_at': 1,
        'rules_json': '[]',
      });
      await main.insert('automation_event', {'ts': 1, 'event': 'run'});
      await main.insert('automation_rule', {'id': 'r1', 'name': 'n'});
      prefs.putString('recognition_members', 'config_json', '{}');
      prefs.putString('recognition_members', 'etag', 'abc');

      final result = await buildService().run(CleanupAction.allData);
      expect(result.removed, greaterThan(0));
      expect(await main.query('dns_log'), isEmpty);
      expect(await main.query('app_traffic_daily'), isEmpty);
      expect(await main.query('mirror_template'), isEmpty);
      expect(await main.query('rule_version'), isEmpty);
      expect(await main.query('automation_event'), isEmpty);
      expect(await main.query('automation_rule'), isEmpty);
      expect(prefs.read('recognition_members', 'config_json'), isNull);
      expect(prefs.read('recognition_members', 'etag'), isNull);
      expect(
        prefs.read(LegacySettings.uiContainer, 'initial_agreement_accepted'),
        isNull,
      );
    });
  });

  group('内核目录', () {
    test('动作标志、表清单与全面清理顺序都来自 Rust', () {
      expect(CleanupAction.settingsGuides.exitsApp, isTrue);
      expect(CleanupAction.allData.exitsApp, isTrue);
      expect(CleanupAction.logs.exitsApp, isFalse);
      expect(CleanupAction.domainRules.affectsEngine, isTrue);
      expect(CleanupAction.logs.affectsEngine, isFalse);
      expect(CleanupPlan.instance.logTables, [
        'dns_log',
        'http_request_log',
        'dns_race_log',
        'bootstrap_log',
      ]);
      expect(CleanupPlan.instance.allDataOrder.last, 'settingsGuides');
      expect(CleanupPlan.instance.allDataTables, isEmpty);
      expect(CleanupPlan.instance.allDataPrefs, isEmpty);
      expect(CleanupPlan.instance.recognitionMembersKeys, [
        'config_json',
        'saved_at_ms',
        'etag',
      ]);
      expect(CleanupPlan.instance.subscriptionVersionTable, 'rule_version');
      expect(CleanupPlan.instance.mirrorTemplateGlobalPrefs, [
        (container: LegacySettings.uiContainer, key: 'global_mirror_enabled'),
        (container: LegacySettings.uiContainer, key: 'global_mirror_template'),
      ]);
    });

    test('全面清理顺序覆盖除 allData 外的全部动作', () {
      final order = CleanupPlan.instance.allDataOrder;
      final expected = {
        for (final action in CleanupAction.values)
          if (action != CleanupAction.allData) action.name,
      };
      expect(order.toSet(), expected);
      expect(order.toSet().length, order.length);
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

void _mockChannel(
  String name,
  Future<Object?> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel(name), handler);
}

void _clearMock(String name) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel(name), null);
}
