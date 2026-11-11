// The aggregates behind the race/bootstrap/subscription drill-downs, the statistics card and the
// traffic page. Those numbers come from Rust; these tests pin the SQL shape and the counting.

import 'package:diting_android/data/db/app_traffic_repository.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/log_race_providers.dart';
import 'package:diting_android/state/log_stats_providers.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_android/state/traffic_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/legacy_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await createLegacySchema(db);
    await db.execute(
      'CREATE TABLE dns_race_log ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'timestamp INTEGER NOT NULL, queryName TEXT NOT NULL, '
      'strategy TEXT NOT NULL, providerCount INTEGER NOT NULL, '
      'success INTEGER NOT NULL, elapsedMs INTEGER NOT NULL, '
      'selectedProviderId TEXT, selectedElapsedMs INTEGER, '
      'winnerProviderId TEXT, winnerElapsedMs INTEGER, '
      'fallbackUsed INTEGER NOT NULL DEFAULT 0, '
      'fallbackSuccess INTEGER NOT NULL DEFAULT 0, message TEXT)',
    );
    await db.execute(
      'CREATE TABLE bootstrap_log ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'timestamp INTEGER NOT NULL, ipId TEXT NOT NULL, ipName TEXT NOT NULL, '
      'ip TEXT NOT NULL, success INTEGER NOT NULL, '
      'elapsedMs INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE subscription ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'name TEXT NOT NULL, enabled INTEGER NOT NULL)',
    );
  });

  tearDown(() => db.close());

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [
        activeLogDatabaseProvider.overrideWith((ref) async => db),
        mainLogDatabaseProvider.overrideWith((ref) async => db),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  int now() => DateTime.now().millisecondsSinceEpoch;

  test('竞速页：总结、命名排行、策略与智能选择', () async {
    final stamp = now();
    Future<void> race({
      required String strategy,
      required bool success,
      String? selected,
      String? winner,
      int elapsed = 20,
      bool fallbackUsed = false,
    }) => db.insert('dns_race_log', {
      'timestamp': stamp,
      'queryName': 'x.example',
      'strategy': strategy,
      'providerCount': 2,
      'success': success ? 1 : 0,
      'elapsedMs': elapsed,
      'selectedProviderId': selected,
      'selectedElapsedMs': selected == null ? null : elapsed,
      'winnerProviderId': winner,
      'winnerElapsedMs': winner == null ? null : elapsed,
      'fallbackUsed': fallbackUsed ? 1 : 0,
      'fallbackSuccess': fallbackUsed ? 1 : 0,
    });
    await race(
      strategy: 'smart_prediction',
      success: true,
      selected: 'preset_alidns_dns',
      winner: 'preset_alidns_dns',
    );
    await race(
      strategy: 'smart_prediction',
      success: true,
      selected: 'preset_alidns_dns',
      winner: 'preset_tencent_dns',
      fallbackUsed: true,
    );
    await race(strategy: 'parallel_race', success: false);

    final snapshot = await container().read(raceStatsProvider.future);
    expect(snapshot.summary.requests, 3);
    expect(snapshot.summary.successes, 2);
    expect(snapshot.entries.map((row) => row.name), contains('阿里云'));
    expect(snapshot.entries.firstWhere((row) => row.name == '阿里云').wins, 1);
    final smart = snapshot.strategyStats.firstWhere(
      (row) => row.strategy == 'smart_prediction',
    );
    expect(smart.label, raceStrategyLabel('smart_prediction'));
    expect(smart.requests, 2);
    expect(smart.primaryWins, 1);
    expect(smart.fallbackUses, 1);
    final selection = snapshot.smartSelections.single;
    expect(selection.name, '阿里云');
    expect(selection.selectedCount, 2);
    expect(selection.selectedSuccesses, 1);
  });

  test('Bootstrap 页：按尝试次数加权平均', () async {
    final stamp = now();
    Future<void> row(String id, int attempts, int elapsed) async {
      for (var i = 0; i < attempts; i++) {
        await db.insert('bootstrap_log', {
          'timestamp': stamp,
          'ipId': id,
          'ipName': id,
          'ip': '1.1.1.1',
          'success': i == 0 ? 1 : 0,
          'elapsedMs': elapsed,
        });
      }
    }

    await row('a', 1, 10);
    await row('b', 3, 20);

    final snapshot = await container().read(bootstrapStatsProvider.future);
    expect(snapshot.attempts, 4);
    expect(snapshot.successes, 2);
    expect(snapshot.failures, 2);
    expect(snapshot.averageElapsedMs, 17.5);
    expect(snapshot.ips, hasLength(2));
  });

  test('订阅拦截页：DNS/HTTPS 命中合并，总数为分母', () async {
    final stamp = now();
    await db.insert('subscription', {'id': 1, 'name': '广告拦截', 'enabled': 1});
    await insertDnsRow(
      db,
      timestamp: stamp,
      queryName: 'ad.example',
      result: 'BLOCKED',
    );
    await db.update(
      'dns_log',
      {'blockSubscriptionId': 1},
      where: 'queryName = ?',
      whereArgs: ['ad.example'],
    );
    await insertDnsRow(
      db,
      timestamp: stamp,
      queryName: 'ok.example',
      result: 'PASSED',
    );
    await insertHttpRow(
      db,
      timestamp: stamp,
      outcome: 'blocked',
      blockSubscriptionId: 9,
    );
    await insertHttpRow(db, timestamp: stamp, outcome: 'allowed');

    final snapshot = await container().read(
      subscriptionInterceptionProvider.future,
    );
    expect(snapshot.totalRequests, 4);
    expect(snapshot.items, hasLength(2));
    final known = snapshot.items.firstWhere((row) => row.id == 1);
    expect(known.name, '广告拦截');
    expect(known.hits, 1);
    expect(known.rate, 0.25);
    final deleted = snapshot.items.firstWhere((row) => row.id == 9);
    expect(deleted.deleted, isTrue);
    expect(deleted.name, contains('已删除订阅'));
    expect(deleted.rate, 0.25);
  });

  test('统计卡：请求数与估算节省字节', () async {
    final stamp = now();
    await insertDnsRow(
      db,
      timestamp: stamp,
      queryName: 'cached.example',
      result: 'PASSED',
      cached: true,
    );
    await insertDnsRow(
      db,
      timestamp: stamp,
      queryName: 'blocked.example',
      result: 'BLOCKED',
    );
    await insertHttpRow(db, timestamp: stamp, outcome: 'blocked');
    await insertHttpRow(db, timestamp: stamp, outcome: 'invalid');
    await db.execute(
      'CREATE TABLE dns_cache ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'queryName TEXT NOT NULL, queryType INTEGER NOT NULL, '
      'expiresAt INTEGER NOT NULL, hitCount INTEGER NOT NULL, '
      'originalTtlSeconds INTEGER NOT NULL, responseSize INTEGER NOT NULL)',
    );
    await db.insert('dns_cache', {
      'queryName': 'cached.example',
      'queryType': 1,
      'expiresAt': stamp + 60000,
      'hitCount': 1,
      'originalTtlSeconds': 300,
      'responseSize': 100,
    });
    await insertTrafficRow(
      db,
      AppTrafficRepository.todayKey(),
      'com.example',
      tx: 10,
      rx: 20,
    );

    final container = ProviderContainer(
      overrides: [
        activeLogDatabaseProvider.overrideWith((ref) async => db),
        mainLogDatabaseProvider.overrideWith((ref) async => db),
      ],
    );
    addTearDown(container.dispose);

    final requests = await container.read(
      logStatsRequestsProvider(TrafficWindow.today).future,
    );
    expect(requests.total, 4);
    expect(requests.blocked, 3);
    expect(requests.cached, 1);
    final data = await container.read(
      logStatsDataProvider(TrafficWindow.today).future,
    );
    expect(data.saved, 100);
    expect(data.uploaded, 10);
    expect(data.downloaded, 20);
  });

  test('流量页：窗口内按时长排行并给出总计', () async {
    final today = AppTrafficRepository.todayKey();
    await insertTrafficRow(db, today, 'com.a', tx: 100, rx: 200);
    await insertTrafficRow(db, today, 'com.b', tx: 10, rx: 20);

    final snapshot = await container().read(trafficSnapshotProvider.future);
    expect(snapshot.startDate, today);
    expect(snapshot.endDate, today);
    expect(snapshot.rows.map((row) => row.packageName), ['com.a', 'com.b']);
    expect(snapshot.txBytes, 110);
    expect(snapshot.rxBytes, 220);
    expect(snapshot.totalBytes, 330);
  });
}
