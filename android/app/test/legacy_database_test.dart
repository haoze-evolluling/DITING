// Exercises the log SQL against the exact 1.4.3 layout read off the device.

import 'package:diting_android/data/db/app_traffic_repository.dart';
import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/legacy_schema.dart';

void main() {
  group('1.4.3 日志表 SQL', _legacyRepository);
}

void _legacyRepository() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await createLegacySchema(db);
  });

  tearDown(() => db.close());

  Future<int> insertHttp({
    required int timestamp,
    required String outcome,
    String packageName = 'com.example.app',
    String? authority,
    String protocol = 'h2',
    String? matchedRule,
    int? blockSubscriptionId,
  }) => insertHttpRow(
    db,
    timestamp: timestamp,
    outcome: outcome,
    packageName: packageName,
    authority: authority,
    protocol: protocol,
    matchedRule: matchedRule,
    blockSubscriptionId: blockSubscriptionId,
  );

  Future<int> insertDns({
    required int timestamp,
    required String queryName,
    required String result,
    int queryType = 1,
    String? message,
    bool cached = false,
    String? packageName,
  }) => insertDnsRow(
    db,
    timestamp: timestamp,
    queryName: queryName,
    result: result,
    queryType: queryType,
    message: message,
    cached: cached,
    packageName: packageName,
  );

  Future<int> insertTraffic(
    String date,
    String packageName, {
    required int tx,
    required int rx,
    String appName = '',
    int updatedAt = 1,
  }) => insertTrafficRow(
    db,
    date,
    packageName,
    tx: tx,
    rx: rx,
    appName: appName,
    updatedAt: updatedAt,
  );

  group('http_request_log 五档筛选', () {
    /// One row per outcome plus an unknown one, which 1.4.3's `else` branch maps to ERROR
    const outcomes = <String>[
      'allowed',
      'rewritten',
      'blocked',
      'invalid',
      'passthrough',
      'bypassed',
      'unsupported_protocol',
      'resource_bypass',
      'decryption_failed',
    ];

    setUp(() async {
      for (final (index, outcome) in outcomes.indexed) {
        await insertHttp(
          timestamp: 1000 + index,
          outcome: outcome,
          authority: 'host$index.example',
        );
      }
    });

    test('每档的 outcome 集合与旧版 where 子句一致', () async {
      final repository = HttpRequestRepository(db);

      Future<Set<String>> outcomesOf(RequestStatus status) async {
        final rows = await repository.recent(status: status);
        return {for (final row in rows) row.outcome};
      }

      expect(await outcomesOf(RequestStatus.passed), {'allowed'});
      expect(await outcomesOf(RequestStatus.rewritten), {'rewritten'});
      expect(await outcomesOf(RequestStatus.blocked), {'blocked', 'invalid'});
      expect(await outcomesOf(RequestStatus.bypassed), {
        'passthrough',
        'bypassed',
        'unsupported_protocol',
        'resource_bypass',
      });
      // `NOT IN` catch-all: an unlisted outcome counts as failed, not passed
      expect(await outcomesOf(RequestStatus.error), {'decryption_failed'});
    });

    test('五档互斥且并集等于全部', () async {
      final repository = HttpRequestRepository(db);
      final buckets = <RequestStatus, Set<int>>{};
      for (final status in RequestStatus.values) {
        if (status == RequestStatus.all) continue;
        buckets[status] = {
          for (final row in await repository.recent(status: status)) row.id,
        };
      }

      final union = <int>{};
      var sum = 0;
      for (final entry in buckets.entries) {
        sum += entry.value.length;
        union.addAll(entry.value);
      }
      final all = await repository.recent();

      expect(union.length, all.length, reason: '并集应覆盖全部行');
      expect(sum, all.length, reason: '各档条数之和应等于总数（互斥）');
    });

    test('关键词匹配 authority / packageName / matchedRule', () async {
      await insertHttp(
        timestamp: 2000,
        outcome: 'blocked',
        authority: 'ads.tracker.example',
        packageName: 'com.game.big',
        matchedRule: 'RULE-SET,广告拦截',
      );
      final repository = HttpRequestRepository(db);

      expect(
        (await repository.recent(query: 'tracker')).map((row) => row.outcome),
        contains('blocked'),
      );
      expect(
        (await repository.recent(query: 'com.game')).single.packageName,
        'com.game.big',
      );
      expect(
        (await repository.recent(query: '广告拦截')).single.matchedRule,
        'RULE-SET,广告拦截',
      );
    });

    test('dailyStats 的窗口过滤掉更早的行', () async {
      final stats = await HttpRequestRepository(db)
          .dailyStats(since: DateTime.fromMillisecondsSinceEpoch(1000 + 4));
      expect(stats.total, outcomes.length - 4);
    });
  });

  group('dns_log 六档筛选', () {
    setUp(() async {
      await insertDns(
        timestamp: 100,
        queryName: 'api.github.com',
        result: 'PASSED',
        packageName: 'com.example.browser',
        message:
            'app=com.example.browser, resolved=140.82.113.6, '
            'elapsed=28ms',
      );
      await insertDns(
        timestamp: 101,
        queryName: 'TCP 1.1.1.1:443',
        result: 'PASSED',
        queryType: 0,
        message: 'app=com.example.app, resolved=1.1.1.1',
      );
      await insertDns(
        timestamp: 102,
        queryName: 'UDP 8.8.8.8:53',
        result: 'PASSED',
        queryType: 0,
        message: 'blocked_by=connection',
      );
      await insertDns(
        timestamp: 103,
        queryName: 'ads.example.com',
        result: 'BLOCKED',
        message: 'blocked_by=firewall:ads, elapsed=1ms',
      );
      await insertDns(
        timestamp: 104,
        queryName: 'rewrite-column.example',
        result: 'REWRITTEN',
        message: 'blocked_by=rewrite=1.2.3.4',
      );
      await insertDns(
        timestamp: 105,
        queryName: 'rewrite-chinese.example',
        result: 'PASSED',
        message: '命中覆写规则 matched rewrite rule elapsed=4ms',
      );
      await insertDns(
        timestamp: 106,
        queryName: 'broken.example',
        result: 'ERROR',
        message: 'error=timeout elapsed=2000ms',
      );
    });

    test('PASSED 排除 TCP / UDP 前缀行与 blocked_by=connection', () async {
      final rows = await DnsQueryRepository(db)
          .recent(status: RequestStatus.passed);
      final names = {for (final row in rows) row.queryName};

      expect(names, contains('api.github.com'));
      expect(names, isNot(contains('TCP 1.1.1.1:443')));
      expect(names, isNot(contains('UDP 8.8.8.8:53')));
      expect(names, isNot(contains('rewrite-column.example')));
      expect(names, isNot(contains('rewrite-chinese.example')));
    });

    test('REWRITTEN 命中结果列、英文短语与中文「覆写」', () async {
      final rows = await DnsQueryRepository(db)
          .recent(status: RequestStatus.rewritten);
      final names = {for (final row in rows) row.queryName};

      expect(names, contains('rewrite-column.example'));
      expect(names, contains('rewrite-chinese.example'));
      expect(names, isNot(contains('api.github.com')));
      expect(names, isNot(contains('TCP 1.1.1.1:443')));
    });

    test('BLOCKED 命中结果列与 blocked_by=firewall:', () async {
      final rows = await DnsQueryRepository(db)
          .recent(status: RequestStatus.blocked);
      final names = {for (final row in rows) row.queryName};

      expect(names, contains('ads.example.com'));
      expect(names, isNot(contains('api.github.com')));
      expect(names, isNot(contains('rewrite-column.example')));
    });

    test('ERROR 只取 result = ERROR', () async {
      final rows = await DnsQueryRepository(db)
          .recent(status: RequestStatus.error);
      expect(rows.single.queryName, 'broken.example');
    });

    test('BYPASSED 命中 queryType = 0 与 TCP / UDP 前缀行', () async {
      final rows = await DnsQueryRepository(db)
          .recent(status: RequestStatus.bypassed);
      final names = {for (final row in rows) row.queryName};

      expect(names, contains('TCP 1.1.1.1:443'));
      expect(names, contains('UDP 8.8.8.8:53'));
      expect(names, isNot(contains('api.github.com')));
      expect(names, isNot(contains('broken.example')));
    });

    test('五档互斥且并集等于全部', () async {
      final repository = DnsQueryRepository(db);
      final all = await repository.recent();
      final union = <int>{};
      var sum = 0;
      for (final status in RequestStatus.values) {
        if (status == RequestStatus.all) continue;
        final ids = {
          for (final row in await repository.recent(status: status)) row.id,
        };
        sum += ids.length;
        union.addAll(ids);
      }

      expect(union.length, all.length, reason: '并集应覆盖全部行');
      expect(sum, all.length, reason: '各档条数之和应等于总数（互斥）');
    });

    test('DnsLogMessage 拆解 app / resolved / blocked_by / error / elapsed', () {
      final parsed = DnsLogMessage.parse(
        'app=com.example.app, resolved=1.1.1.1, blocked_by=firewall:ads, '
        'error=boom, elapsed=42ms',
      );

      expect(parsed.app, 'com.example.app');
      expect(parsed.resolved, '1.1.1.1');
      expect(parsed.blockedBy, 'firewall:ads');
      expect(parsed.error, 'boom');
      expect(parsed.elapsedMs, 42);
    });
  });

  group('app_traffic_daily', () {
    setUp(() async {
      // Totals differ on purpose: equal totals make the `ORDER BY` a tie with no stable order
      await insertTraffic('2026-10-19', 'com.a', tx: 10, rx: 90, appName: '甲');
      await insertTraffic('2026-10-19', 'com.b', tx: 70, rx: 50, appName: '乙');
      await insertTraffic('2026-10-20', 'com.a', tx: 20, rx: 80, appName: '甲');
      await insertTraffic('2026-10-18', 'com.c', tx: 1, rx: 9, appName: '丙');
    });

    test('byDate 按总量降序', () async {
      final rows = await AppTrafficRepository(db).byDate('2026-10-19');

      expect(rows.map((row) => row.packageName), ['com.b', 'com.a']);
      expect(rows.first.totalBytes, 120);
      expect(rows.last.rxBytes, 90);
    });

    test('dateRange 按包名求和并取最早日期', () async {
      final rows = await AppTrafficRepository(db)
          .dateRange('2026-10-19', '2026-10-20');

      expect(rows, hasLength(2));
      final a = rows.firstWhere((row) => row.packageName == 'com.a');
      expect(a.txBytes, 30, reason: '两天相加');
      expect(a.rxBytes, 170);
      expect(a.totalBytes, 200);
      expect(a.date, '2026-10-19', reason: '旧版 min(date)');
      expect(a.appName, '甲');
      expect(rows.first.packageName, 'com.a');
    });

    test('shareOf 对零总量返回 0 而不是除零', () {
      const row = AppTrafficDaily(
        date: '2026-10-20',
        packageName: 'com.a',
        appName: '甲',
        txBytes: 1,
        rxBytes: 1,
        updatedAt: 0,
      );
      expect(row.shareOf(0), 0);
      expect(row.shareOf(4), 0.5);
    });

    test('today 用本地时区的 yyyy-MM-dd', () async {
      final key = AppTrafficRepository.todayKey();
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key), isTrue);

      await insertTraffic(key, 'com.today', tx: 5, rx: 5, appName: '今');
      final rows = await AppTrafficRepository(db).today();
      expect(rows.map((row) => row.packageName), contains('com.today'));
    });
  });

  group('空库', () {
    test('三个仓储的空查询返回空列表而不是抛错', () async {
      expect(await HttpRequestRepository(db).recent(), isEmpty);
      expect(
        await HttpRequestRepository(db)
            .dailyStats(since: DateTime.fromMillisecondsSinceEpoch(0)),
        isA<HttpRequestDailyStats>().having((stats) => stats.total, 'total', 0),
      );
      expect(await DnsQueryRepository(db).recent(), isEmpty);
      for (final status in RequestStatus.values) {
        expect(await DnsQueryRepository(db).recent(status: status), isEmpty);
        expect(await HttpRequestRepository(db).recent(status: status), isEmpty);
      }
      expect(await AppTrafficRepository(db).byDate('2026-10-20'), isEmpty);
      expect(await AppTrafficRepository(db).allHistory(), isEmpty);
      expect(
        await AppTrafficRepository(db).dateRange('2026-01-01', '2026-12-31'),
        isEmpty,
      );
    });
  });
}

/// Runs the subscription SQL against the real 1.4.3 tables: `ORDER BY`, conflicts, cascades
