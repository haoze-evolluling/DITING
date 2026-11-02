part of 'dashboard_data_test.dart';

/// Pins 1.4.3 `RaceLogDao.strategyStats`: `primaryWins` needs the primary to win and succeed,
/// `selectedSuccesses` excludes fallback rescues, and `since` filters on `timestamp`

void _raceStats() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
  });

  tearDown(() => db.close());

  int now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> insert({
    required String strategy,
    required bool success,
    String? selected,
    String? winner,
    int elapsedMs = 20,
    bool fallbackUsed = false,
    bool fallbackSuccess = false,
    int? timestamp,
  }) => db.insert('dns_race_log', {
    'timestamp': timestamp ?? now(),
    'queryName': 'x.example',
    'strategy': strategy,
    'providerCount': 2,
    'success': success ? 1 : 0,
    'elapsedMs': elapsedMs,
    'selectedProviderId': selected,
    'selectedElapsedMs': selected == null ? null : elapsedMs,
    'winnerProviderId': winner,
    'winnerElapsedMs': winner == null ? null : elapsedMs,
    'fallbackUsed': fallbackUsed ? 1 : 0,
    'fallbackSuccess': fallbackSuccess ? 1 : 0,
  });

  group('strategyStats', () {
    test('按策略分组，primaryWins 只算「首选即胜出且成功」', () async {
      await insert(
        strategy: 'smart_prediction',
        success: true,
        selected: 'a',
        winner: 'a',
      );
      await insert(
        strategy: 'smart_prediction',
        success: true,
        selected: 'a',
        winner: 'b',
        fallbackUsed: true,
        fallbackSuccess: true,
      );
      await insert(strategy: 'smart_prediction', success: false, selected: 'a');
      await insert(strategy: 'parallel_race', success: true, winner: 'c');

      final rows = await RaceLogRepository(db).strategyStats();
      final smart = rows.firstWhere((r) => r.strategy == 'smart_prediction');
      expect(smart.requests, 3);
      expect(smart.successes, 2);
      expect(smart.failures, 1);
      expect(smart.primaryWins, 1, reason: '只有首选即胜出的那一次算');
      expect(smart.fallbackUses, 1);
      expect(smart.primaryWinRate, closeTo(1 / 3, 1e-9));

      final parallel = rows.firstWhere((r) => r.strategy == 'parallel_race');
      expect(parallel.primaryWins, 0);
      expect(parallel.successRate, 1);
    });

    test('窗口过滤：更早的行不进今日聚合', () async {
      final yesterday = now() - const Duration(days: 1).inMilliseconds;
      await insert(
        strategy: 'smart_prediction',
        success: true,
        selected: 'a',
        winner: 'a',
        timestamp: yesterday,
      );
      final since = DateTime.now().subtract(const Duration(hours: 1));
      final rows = await RaceLogRepository(db)
          .strategyStats(since: since.millisecondsSinceEpoch);
      expect(rows, isEmpty);
    });
  });

  group('smartSelectionStats', () {
    test('selectedSuccesses 排除兜底救回，且只统计智能选择', () async {
      await insert(
        strategy: 'smart_prediction',
        success: true,
        selected: 'a',
        winner: 'a',
      );
      await insert(
        strategy: 'smart_prediction',
        success: true,
        selected: 'a',
        winner: 'b',
        fallbackUsed: true,
        fallbackSuccess: true,
      );
      await insert(
        strategy: 'primary_backup',
        success: true,
        selected: 'a',
        winner: 'a',
      );

      final rows = await RaceLogRepository(db).smartSelectionStats();
      expect(rows, hasLength(1));
      final a = rows.single;
      expect(a.providerId, 'a');
      expect(a.selectedCount, 2);
      expect(a.selectedSuccesses, 1);
      expect(a.selectedSuccessRate, closeTo(0.5, 1e-9));
    });
  });

  group('raceStrategyLabel', () {
    test('历史别名与落盘值都翻成中文，未知值原样返回', () {
      expect(raceStrategyLabel('brute_force_parallel'), '最快响应');
      expect(raceStrategyLabel('race'), '最快响应');
      expect(raceStrategyLabel('parallel_race'), '最快响应');
      expect(raceStrategyLabel('smart_prediction'), '智能选择');
      expect(raceStrategyLabel('prediction'), '智能选择');
      expect(raceStrategyLabel('primary_backup'), '依次尝试');
      expect(raceStrategyLabel('single'), '单服务商');
      expect(raceStrategyLabel('weird'), 'weird');
    });
  });
}

/// Guards real-data wiring in the database: no bucket counted as passed, no demo fallback

void _siteLatencyCatalog() {
  test('id 与 host 都不重复', () {
    final ids = [for (final target in siteLatencyTargets) target.id];
    final hosts = [for (final target in siteLatencyTargets) target.host];
    expect(ids.toSet().length, ids.length);
    expect(hosts.toSet().length, hosts.length);
  });

  test('站点大幅扩充且每个分类都有站点', () {
    expect(siteLatencyTargets.length, greaterThanOrEqualTo(44));
    for (final category in SiteCategory.values) {
      expect(
        siteLatencyInCategory(category),
        isNotEmpty,
        reason: '${category.label} 分类为空',
      );
    }
    final grouped = [
      for (final category in SiteCategory.values)
        ...siteLatencyInCategory(category),
    ];
    expect(grouped.length, siteLatencyTargets.length);
  });

  test('默认四个站点都在目录里', () {
    for (final id in defaultDashboardSiteIds) {
      expect(siteLatencyById(id), isNotNull, reason: id);
    }
    expect(defaultDashboardSiteIds.length, dashboardSiteCount);
  });

  test('解析出的仪表盘站点总是四个且不重复', () {
    expect(resolveDashboardSites(const []), hasLength(dashboardSiteCount));
    expect(
      resolveDashboardSites(const ['no_such_site']),
      hasLength(dashboardSiteCount),
    );
    final picked = resolveDashboardSites(const [
      'github',
      'github',
      'steam',
      'netflix',
      'spotify',
    ]);
    expect(picked.map((target) => target.id), [
      'github',
      'steam',
      'netflix',
      'spotify',
    ]);
  });
}
