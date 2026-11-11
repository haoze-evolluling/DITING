// Providers wired to real tables: the overview aggregation and the log
// refresh timer that keeps the dashboard live.

import 'package:diting_android/data/db/mirror_template_repository.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/log_dashboard_overview_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/log_refresh_providers.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/legacy_schema.dart';

void main() {
  group('概览聚合', _realDataWiring);
  group('日志定时刷新', _logRefresh);
}

void _realDataWiring() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await createLegacySchema(db);
    await db.execute(
      'CREATE TABLE dns_cache ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'queryName TEXT NOT NULL, queryType INTEGER NOT NULL, '
      'expiresAt INTEGER NOT NULL, hitCount INTEGER NOT NULL DEFAULT 0, '
      'originalTtlSeconds INTEGER NOT NULL, responseSize INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE dns_race_log ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'timestamp INTEGER NOT NULL, queryName TEXT NOT NULL, '
      'strategy TEXT NOT NULL, providerCount INTEGER NOT NULL, '
      'success INTEGER NOT NULL, elapsedMs INTEGER NOT NULL, '
      'winnerProviderId TEXT, winnerElapsedMs INTEGER, message TEXT)',
    );
    await db.execute(
      'CREATE TABLE bootstrap_log ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'timestamp INTEGER NOT NULL, ipId TEXT NOT NULL, ipName TEXT NOT NULL, '
      'ip TEXT NOT NULL, success INTEGER NOT NULL, elapsedMs INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE subscription ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'name TEXT NOT NULL, url TEXT NOT NULL, enabled INTEGER NOT NULL, '
      'sourceType TEXT NOT NULL, kind TEXT NOT NULL, '
      'groupId INTEGER, ruleCount INTEGER NOT NULL, '
      'addedAt INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE mirror_template ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'name TEXT NOT NULL, template TEXT NOT NULL, addedAt INTEGER NOT NULL)',
    );
  });

  tearDown(() => db.close());

  ProviderContainer containerFor({bool filtered = false}) {
    final container = ProviderContainer(
      overrides: [
        activeLogDatabaseProvider.overrideWith((ref) async => db),
        mainLogDatabaseProvider.overrideWith((ref) async => db),
        if (filtered) logModeProvider.overrideWith(_FilteredLogMode.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  int now() => DateTime.now().millisecondsSinceEpoch;

  group('概览聚合（logDashboardProvider）', () {
    test('DNS 与 HTTPS 两表按旧版口径相加', () async {
      final stamp = now();
      await insertDnsRow(
        db,
        timestamp: stamp,
        queryName: 'a.example',
        result: 'PASSED',
        message: 'elapsed=10ms',
      );
      await insertDnsRow(
        db,
        timestamp: stamp,
        queryName: 'b.example',
        result: 'PASSED',
        cached: true,
        message: 'elapsed=20ms',
      );
      await insertDnsRow(
        db,
        timestamp: stamp,
        queryName: 'c.example',
        result: 'BLOCKED',
      );
      await insertHttpRow(db, timestamp: stamp, outcome: 'allowed');
      await insertHttpRow(db, timestamp: stamp, outcome: 'blocked');
      await insertHttpRow(db, timestamp: stamp, outcome: 'passthrough');
      await insertHttpRow(db, timestamp: stamp, outcome: 'invalid');

      final snapshot = await containerFor().read(logDashboardProvider.future);
      expect(snapshot.breakdown.passed, 3);
      expect(snapshot.breakdown.blocked, 3);
      expect(snapshot.breakdown.bypassed, 1);
      expect(snapshot.breakdown.error, 0);
      expect(snapshot.breakdown.cached, 1);
      expect(snapshot.breakdown.total, 7);
      expect(snapshot.quality.averageLatencyMs, 15);
      expect(snapshot.quality.latencySamples, 2);
      expect(snapshot.quality.cacheHitRate, closeTo(1 / 2, 1e-9));
    });

    test('昨天的行不进今日计数，但「最近请求」仍取最新几条', () async {
      final yesterday = now() - const Duration(days: 1).inMilliseconds;
      await insertDnsRow(
        db,
        timestamp: yesterday,
        queryName: 'old.example',
        result: 'PASSED',
      );
      await insertHttpRow(db, timestamp: yesterday, outcome: 'allowed');

      final snapshot = await containerFor().read(logDashboardProvider.future);
      expect(snapshot.breakdown.total, 0);
      expect(snapshot.recentRequests, hasLength(2));
    });

    test('最近请求合并两表并按时间倒序，取前五条', () async {
      final base = now();
      for (var i = 0; i < 6; i++) {
        await insertDnsRow(
          db,
          timestamp: base - i * 1000,
          queryName: 'dns$i.example',
          result: 'PASSED',
        );
      }
      await insertHttpRow(
        db,
        timestamp: base + 500,
        outcome: 'allowed',
        authority: 'newest.example',
      );

      final snapshot = await containerFor().read(logDashboardProvider.future);
      expect(snapshot.recentRequests, hasLength(5));
      expect(snapshot.recentRequests.first.name, 'newest.example');
      expect(snapshot.recentRequests.first.source, 'HTTPS');
      expect(snapshot.recentRequests[1].name, 'dns0.example');
    });

    test('缓存热点按命中次数排序，过期行不出现', () async {
      final stamp = now();
      Future<void> cache(
        String name, {
        required int hits,
        required int ttlMs,
      }) => db.insert('dns_cache', {
        'queryName': name,
        'queryType': 1,
        'expiresAt': stamp + ttlMs,
        'hitCount': hits,
        'originalTtlSeconds': 300,
        'responseSize': 64,
      });
      await cache('cold.example', hits: 1, ttlMs: 60000);
      await cache('hot.example', hits: 9, ttlMs: 60000);
      await cache('expired.example', hits: 99, ttlMs: -1000);

      final snapshot = await containerFor().read(logDashboardProvider.future);
      expect(
        [for (final row in snapshot.cacheHotspots) row.queryName],
        ['hot.example', 'cold.example'],
      );
      expect(snapshot.cacheHotspots.first.queryType, 'A');
      expect(snapshot.offMode.cacheEntries, 2);
      expect(snapshot.offMode.cacheHits, 109);
    });

    test('竞速与 Bootstrap 取今日窗口，并解析服务商显示名', () async {
      final stamp = now();
      await db.insert('dns_race_log', {
        'timestamp': stamp,
        'queryName': 'x.example',
        'strategy': 'parallel',
        'providerCount': 3,
        'success': 1,
        'elapsedMs': 20,
        'winnerProviderId': 'preset_alidns_dns',
        'winnerElapsedMs': 12,
      });
      await db.insert('dns_race_log', {
        'timestamp': stamp,
        'queryName': 'y.example',
        'strategy': 'parallel',
        'providerCount': 3,
        'success': 0,
        'elapsedMs': 3000,
        'winnerProviderId': null,
        'winnerElapsedMs': null,
      });
      await db.insert('bootstrap_log', {
        'timestamp': stamp,
        'ipId': 'ip1',
        'ipName': '主节点',
        'ip': '223.5.5.5',
        'success': 1,
        'elapsedMs': 30,
      });

      final snapshot = await containerFor().read(logDashboardProvider.future);
      expect(snapshot.race.requests, 2);
      expect(snapshot.race.successes, 1);
      expect(snapshot.race.successRate, 0.5);
      expect(snapshot.raceWinners, hasLength(1));
      expect(snapshot.raceWinners.single.name, '阿里云');
      expect(snapshot.bootstrap.attempts, 1);
      expect(snapshot.bootstrap.successRate, 1);
      expect(snapshot.bootstrapIps.single.ip, '223.5.5.5');
      expect(snapshot.offMode.raceRequests, 2);
      expect(snapshot.offMode.bootstrapAttempts, 1);
    });

    test('订阅拦截按 blockSubscriptionId 归并，已删订阅标「已删除」', () async {
      final stamp = now();
      await db.insert('subscription', {
        'name': '广告拦截',
        'url': 'https://example.com/ads.txt',
        'enabled': 1,
        'sourceType': 'remote',
        'kind': 'rules',
        'ruleCount': 100,
        'addedAt': stamp,
      });
      for (final (name, subscriptionId) in [
        ('ad.example', 1),
        ('gone.example', 7),
      ]) {
        await db.insert('dns_log', {
          'timestamp': stamp,
          'queryName': name,
          'queryType': 1,
          'result': 'BLOCKED',
          'cached': 0,
          'blockSubscriptionId': subscriptionId,
        });
      }

      final snapshot = await containerFor().read(logDashboardProvider.future);
      final blocks = snapshot.subscriptionBlocks;
      expect(blocks, hasLength(2));
      expect(blocks.first.hits, 1);
      final names = {for (final block in blocks) block.name};
      expect(names, containsAll(['广告拦截', '已删除订阅 #7']));
      final deleted = blocks.firstWhere((block) => block.deleted);
      expect(deleted.statusLabel, '已删除');
      expect(blocks.first.rate, closeTo(1 / 2, 1e-9));
    });

    test('仅拦截与错误模式：DNS 侧通过/缓存归零，HTTPS 只留非通过行', () async {
      final stamp = now();
      await insertDnsRow(
        db,
        timestamp: stamp,
        queryName: 'ok.example',
        result: 'PASSED',
        cached: true,
      );
      await insertDnsRow(
        db,
        timestamp: stamp,
        queryName: 'bad.example',
        result: 'BLOCKED',
      );
      await insertHttpRow(
        db,
        timestamp: stamp,
        outcome: 'allowed',
        authority: 'allowed.example',
      );
      await insertHttpRow(
        db,
        timestamp: stamp,
        outcome: 'blocked',
        authority: 'blocked.example',
      );

      final snapshot = await containerFor(filtered: true)
          .read(logDashboardProvider.future);
      expect(snapshot.breakdown.passed, 0);
      expect(snapshot.breakdown.cached, 0);
      expect(snapshot.breakdown.blocked, 2);
      expect(snapshot.quality.cacheHitRate, 0);
      expect(snapshot.recentRequests, hasLength(2));
      final names = [for (final row in snapshot.recentRequests) row.name];
      expect(names, containsAll(['bad.example', 'blocked.example']));
      expect(names, isNot(contains('ok.example')));
      expect(names, isNot(contains('allowed.example')));
    });

    test('关闭日志模式：不读日志表，但缓存与竞速仍在统计', () async {
      final stamp = now();
      await insertDnsRow(
        db,
        timestamp: stamp,
        queryName: 'quiet.example',
        result: 'PASSED',
      );
      await db.insert('dns_cache', {
        'queryName': 'cached.example',
        'queryType': 1,
        'expiresAt': stamp + 60000,
        'hitCount': 3,
        'originalTtlSeconds': 300,
        'responseSize': 64,
      });

      final container = ProviderContainer(
        overrides: [
          activeLogDatabaseProvider.overrideWith((ref) async => db),
          mainLogDatabaseProvider.overrideWith((ref) async => db),
          logModeProvider.overrideWith(_OffLogMode.new),
        ],
      );
      addTearDown(container.dispose);
      final snapshot = await container.read(logDashboardProvider.future);
      expect(snapshot.breakdown.total, 0);
      expect(snapshot.recentRequests, isEmpty);
      expect(snapshot.subscriptionBlocks, isEmpty);
      expect(snapshot.quality.averageLatencyMs, isNull);
      expect(snapshot.offMode.cacheEntries, 1);
      expect(snapshot.offMode.cacheHits, 3);
    });
  });

  group('镜像站模板（mirror_template）', () {
    test('写入后读得到，同名拒绝而不是覆盖', () async {
      final repository = MirrorTemplateRepository(db);
      final id = await repository.insert(
        name: 'GitHub 镜像',
        template: 'https://ghproxy.example.com/{url}',
      );
      expect(id, isNotNull);
      expect(await repository.all(), hasLength(1));

      final duplicate = await repository.insert(
        name: 'GitHub 镜像',
        template: 'https://other.example.com/{url}',
      );
      expect(duplicate, isNull, reason: '同名唯一索引必须拒绝，不能静默覆盖');
      expect(
        (await repository.byName('GitHub 镜像'))!.template,
        'https://ghproxy.example.com/{url}',
      );
    });
  });
}

class _FilteredLogMode extends LogModeNotifier {
  @override
  LegacyLogMode build() => LegacyLogMode.blockedAndErrors;
}

class _OffLogMode extends LogModeNotifier {
  @override
  LegacyLogMode build() => LegacyLogMode.off;
}

/// The log cards read tables the native writers keep filling; the timer is what makes
/// `CacheHotspotsCard` / `BootstrapDnsCard` update without a manual refresh.

void _logRefresh() {
  test('tick 递增共享 revision，日志 provider 随之重查', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final before = container.read(dnsLogRevisionProvider);
    container.read(logLiveRefreshProvider.notifier).tick();
    expect(container.read(dnsLogRevisionProvider), before + 1);
  });

  testWidgets('挂载后定时刷新一次，不依赖手动点刷新', (tester) async {
    debugDisableDashboardLiveUpdates = false;
    addTearDown(() => debugDisableDashboardLiveUpdates = false);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final before = container.read(dnsLogRevisionProvider);
    container.read(logLiveRefreshProvider.notifier).attachPolling();
    await tester.pump(logLiveRefreshInterval + const Duration(seconds: 1));

    expect(container.read(dnsLogRevisionProvider), before + 1);
    container.read(logLiveRefreshProvider.notifier).detachPolling();
  });

  testWidgets('引用计数：多页共用定时器，最后一个 detach 才停', (tester) async {
    debugDisableDashboardLiveUpdates = false;
    addTearDown(() => debugDisableDashboardLiveUpdates = false);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(logLiveRefreshProvider.notifier);

    notifier.attachPolling();
    notifier.attachPolling();
    notifier.detachPolling();

    final before = container.read(dnsLogRevisionProvider);
    await tester.pump(logLiveRefreshInterval + const Duration(seconds: 1));
    expect(container.read(dnsLogRevisionProvider), before + 1);

    // Last detach stops the timer: no further bumps.
    notifier.detachPolling();
    final after = container.read(dnsLogRevisionProvider);
    await tester.pump(logLiveRefreshInterval * 3);
    expect(container.read(dnsLogRevisionProvider), after);
  });
}

/// The catalog feeds both the card and the detail page, so a duplicate id or an empty category
/// would show up as a missing row rather than an error.
