// Guards real data reaching the two observability pages. Providers are
// overridden because `sqflite_common_ffi` I/O never advances under fake async.

import 'package:diting_android/data/db/app_traffic_repository.dart';
import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/db/rule_providers.dart';
import 'package:diting_android/data/db/dns_cache_repository.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/pages/logs/logs_cache_detail.dart';
import 'package:diting_android/pages/observability/requests_page.dart';
import 'package:diting_android/pages/traffic/traffic_page.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_android/state/rules_providers.dart';
import 'package:diting_android/state/traffic_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

void main() {
  group('请求与流量页', _observabilityPages);
}

class _EmptyRules extends InitialRulesNotifier {
  @override
  Map<RuleKind, List<MockRule>> build() => {
    for (final kind in RuleKind.values) kind: const [],
  };
}

void _observabilityPages() {
  const today = '2026-10-20';

  final dnsRows = <DnsLogRow>[
    DnsLogRow(
      id: 1,
      timestamp: DateTime(2026, 10, 20, 13, 40).millisecondsSinceEpoch,
      queryName: 'api.github.com',
      queryType: 1,
      result: 'PASSED',
      cached: false,
      message: 'app=com.example.browser, resolved=140.82.113.6, elapsed=28ms',
      packageName: 'com.example.browser',
    ),
    DnsLogRow(
      id: 2,
      timestamp: DateTime(2026, 10, 20, 13, 39).millisecondsSinceEpoch,
      queryName: 'TCP 1.1.1.1:443',
      queryType: 0,
      result: 'PASSED',
      cached: false,
      message: 'blocked_by=connection',
    ),
    DnsLogRow(
      id: 3,
      timestamp: DateTime(2026, 10, 20, 13, 38).millisecondsSinceEpoch,
      queryName: 'broken.example',
      queryType: 1,
      result: 'ERROR',
      cached: false,
      message: 'error=timeout elapsed=2000ms',
    ),
  ];

  final httpRecords = <HttpRequestRecord>[
    HttpRequestRecord(
      id: 1,
      timestamp: DateTime(2026, 10, 20, 13, 42).millisecondsSinceEpoch,
      packageName: 'com.example.browser',
      protocol: 'h2',
      outcome: 'allowed',
      authority: 'api.github.com',
      matchedRule: 'DOMAIN-SUFFIX,github.com',
    ),
    HttpRequestRecord(
      id: 2,
      timestamp: DateTime(2026, 10, 20, 13, 41).millisecondsSinceEpoch,
      packageName: 'com.example.ads',
      protocol: 'http/1.1',
      outcome: 'blocked',
      matchedRule: 'RULE-SET,广告拦截',
    ),
  ];

  final trafficRows = <AppTrafficDaily>[
    const AppTrafficDaily(
      date: today,
      packageName: 'com.example.browser',
      appName: '浏览器',
      txBytes: 1000,
      rxBytes: 9000,
      updatedAt: 1,
    ),
    const AppTrafficDaily(
      date: today,
      packageName: 'com.example.ads',
      appName: '',
      txBytes: 200,
      rxBytes: 300,
      updatedAt: 1,
    ),
  ];

  RequestFeed buildFeed() {
    final items = <ObservedRequest>[
      for (final row in dnsRows) ObservedRequest.fromDns(row),
      for (final record in httpRecords) ObservedRequest.fromHttp(record),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return RequestFeed(items: items, hasMore: false);
  }

  /// Whole-list loader for the pages whose feed content is not what they assert on.
  RequestFeedPageLoader wholeFeed() => (
    ref,
    query, {
    String? packageName,
    int? before,
    bool watch = false,
  }) async {
    final feed = buildFeed();
    return (items: feed.items, hasMore: false, cursor: null);
  };

  List<Override> defaultOverrides() => [
    requestFeedPageLoaderProvider.overrideWithValue(wholeFeed()),
    dnsQueryWindowProvider.overrideWith((ref) async => dnsRows),
    dnsQueriesProvider.overrideWith((ref) async => dnsRows),
    trafficSnapshotProvider.overrideWith(
      (ref) async =>
          TrafficSnapshot(rows: trafficRows, startDate: today, endDate: today),
    ),
  ];

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    List<Override>? providerOverrides,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: providerOverrides ?? defaultOverrides(),
        child: AppHost(child: page),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('请求页', () {
    testWidgets('渲染 http_request_log 与 dns_log 的合并结果', (tester) async {
      await pumpPage(tester, const RequestsPage());
      expect(tester.takeException(), isNull);

      expect(find.text('api.github.com'), findsNWidgets(2));
      expect(find.text('DNS'), findsWidgets);
      expect(find.text('HTTPS'), findsWidgets);
      expect(find.textContaining('共 5 条'), findsOneWidget);
      expect(find.textContaining('1 条处理失败'), findsOneWidget);
    });

    testWidgets('读取失败给出重试入口，而不是空白或崩溃', (tester) async {
      await pumpPage(
        tester,
        const RequestsPage(),
        providerOverrides: [
          requestFeedPageLoaderProvider.overrideWithValue((
            ref,
            query, {
            String? packageName,
            int? before,
            bool watch = false,
          }) async => throw StateError('legacy db is locked')),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('无法读取请求记录'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.textContaining('legacy db is locked'), findsOneWidget);
    });

    testWidgets('首屏只取一页，滑到底部再按页取下一批', (tester) async {
      // 120 rows against a 50-row page: the first screen must read 50 and stop, otherwise the
      // page is back to loading everything up front.
      final all = [
        for (var index = 0; index < 120; index++)
          ObservedRequest.fromDns(
            DnsLogRow(
              id: index,
              timestamp:
                  DateTime(2026, 10, 20, 13).millisecondsSinceEpoch - index,
              queryName: 'host$index.example',
              queryType: 1,
              result: 'PASSED',
              cached: false,
              message: '',
            ),
          ),
      ];
      final reads = <int?>[];
      await pumpPage(
        tester,
        const RequestsPage(),
        providerOverrides: [
          // Cursor paging: every read takes 50 rows at or below the cursor, so page N costs the
          // same as page 1 instead of re-reading everything above it.
          requestFeedPageLoaderProvider.overrideWithValue((
            ref,
            query, {
            String? packageName,
            int? before,
            bool watch = false,
          }) async {
            reads.add(before);
            final eligible = before == null
                ? all
                : [
                    for (final item in all)
                      if (item.timestamp <= before) item,
                  ];
            final window = eligible.take(50).toList(growable: false);
            return (
              items: window,
              hasMore: eligible.length > 50,
              cursor: window.isEmpty ? before : window.last.timestamp,
            );
          }),
        ],
      );
      expect(tester.takeException(), isNull);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(RequestsPage)),
      );
      expect(
        container.read(requestFeedProvider).requireValue.items,
        hasLength(50),
      );
      expect(reads, [null]);

      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await tester.pumpAndSettle();
      // One drag can reveal several pages: after a page lands the viewport is still near the end,
      // so the listener asks again. Every follow-up read carries a cursor.
      expect(reads.length, greaterThan(1));
      expect(reads.skip(1).every((cursor) => cursor != null), isTrue);
      expect(
        container.read(requestFeedProvider).requireValue.items.length,
        greaterThan(50),
      );

      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -20000));
        await tester.pumpAndSettle();
      }
      final feed = container.read(requestFeedProvider).requireValue;
      expect(feed.items, hasLength(120));
      expect(feed.hasMore, isFalse);
      expect(find.textContaining('共 120 条'), findsOneWidget);
      expect(find.textContaining('已加载全部'), findsOneWidget);
    });

    testWidgets('详情页可复制域名并加入黑白名单，纯 IP 记录禁用规则按钮', (tester) async {
      await pumpPage(
        tester,
        RequestDetailSheet(request: ObservedRequest.fromDns(dnsRows.first)),
        providerOverrides: [
          ruleRepositoryProvider.overrideWith((ref) => null),
          initialRulesProvider.overrideWith(_EmptyRules.new),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('复制域名'), findsOneWidget);

      await tester.tap(find.text('加入黑名单'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RequestDetailSheet)),
      );
      expect(
        container.read(rulesOfKindProvider(RuleKind.block)).single.pattern,
        'api.github.com',
      );
      expect(find.text('已在黑名单'), findsOneWidget);

      await tester.tap(find.text('加入白名单'));
      await tester.pumpAndSettle();
      expect(find.text('已在白名单'), findsOneWidget);

      await pumpPage(
        tester,
        RequestDetailSheet(request: ObservedRequest.fromDns(dnsRows[1])),
        providerOverrides: [
          ruleRepositoryProvider.overrideWith((ref) => null),
          initialRulesProvider.overrideWith(_EmptyRules.new),
        ],
      );
      expect(find.text('复制地址'), findsOneWidget);
      expect(find.textContaining('域名规则无法匹配'), findsOneWidget);
    });
  });

  testWidgets('DNS 缓存详情复用请求详情的域名操作', (tester) async {
    await pumpPage(
      tester,
      DnsCacheDetailSheet(
        entry: DnsCacheRecord(
          domain: 'cdn.example.com',
          queryType: 1,
          expiresAt: DateTime.now().millisecondsSinceEpoch + 300 * 1000,
          hitCount: 12,
          originalTtlSeconds: 600,
          responseSize: 64,
        ),
      ),
      providerOverrides: [
        ruleRepositoryProvider.overrideWith((ref) => null),
        initialRulesProvider.overrideWith(_EmptyRules.new),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('复制域名'), findsOneWidget);
    expect(find.text('尚未命中'), findsOneWidget);

    await tester.tap(find.text('加入白名单'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DnsCacheDetailSheet)),
    );
    expect(
      container.read(rulesOfKindProvider(RuleKind.allow)).single.pattern,
      'cdn.example.com',
    );
    expect(find.text('已在白名单'), findsOneWidget);
  });

  group('流量页', () {
    testWidgets('渲染 app_traffic_daily 排行，实时速率如实来自原生', (tester) async {
      await pumpPage(tester, const TrafficPage());
      expect(tester.takeException(), isNull);

      expect(find.text('浏览器'), findsOneWidget);
      // The ranking is a lazily built sliver, so the second row only exists after a scroll.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.textContaining('com.example.ads'), findsWidgets);
      expect(find.text('实时速率'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('会话曲线'), findsNothing);
      expect(find.textContaining('不反映真实网速'), findsNothing);
    });

    testWidgets('没有原生速率通道时说明缺失，而不是画 0 的平线', (tester) async {
      await pumpPage(
        tester,
        const TrafficPage(),
        providerOverrides: [
          ...defaultOverrides(),
          speedSeriesProvider.overrideWith(
            () => _FakeSpeedSeries(
              const SpeedSeries(
                samples: [],
                revision: 0,
                source: SpeedSource.noNativeChannel,
              ),
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('本模式不统计实时速率'), findsOneWidget);
      expect(find.textContaining('都是真实数字'), findsOneWidget);
    });

    testWidgets('带旧版的时间窗口、搜索、排序与隐藏系统应用', (tester) async {
      await pumpPage(tester, const TrafficPage());
      expect(tester.takeException(), isNull);

      expect(find.text('今日'), findsWidgets);
      expect(find.text('本周'), findsWidgets);
      expect(find.text('本月'), findsWidgets);
      expect(find.text('全部历史'), findsWidgets);
      expect(find.text('隐藏系统应用'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);

      // The row carries the card's inset, so the tile fills the card: a card padding would
      // leave the pressed state as a square patch inside the rounded card.
      final title = find.text('隐藏系统应用');
      expect(
        tester.getRect(
          find.ancestor(of: title, matching: find.byType(ListTile)),
        ),
        tester.getRect(
          find.ancestor(of: title, matching: find.byType(FilledButton)),
        ),
      );
    });
  });
}

// `Override` is only exported from `misc.dart`, and override lists need `List<Override>`

/// Guards real data reaching the two observability pages. Providers are overridden because
/// `sqflite_common_ffi` I/O never advances under fake async, so `pumpAndSettle` times out
class _FakeSpeedSeries extends SpeedSeriesNotifier {
  _FakeSpeedSeries(this._value);

  final SpeedSeries _value;

  @override
  SpeedSeries build() => _value;
}

/// The card probes on its own first frame, and its header must then report the tally for the
/// sites it actually drew — a mismatch between the chip and the cells is what the emulator showed.
