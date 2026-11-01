// Desktop log branch (docs/development/flutter-desktop-ui.md step 4): the service's 24-hour
// summary and rankings, its live query stream and its query log with the console's search
// conditions and offset paging. Every figure and row must come from the API; a failed read says so
// instead of showing an empty table, and a socket that is down says so instead of looking quiet.

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_event_client.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/pages/logs/desktop_logs_page.dart';
import 'package:diting/desktop/pages/logs/widgets/log_live_panel.dart';
import 'package:diting/desktop/pages/logs/widgets/log_query_table.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpLogs(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 800),
    Map<String, Map<String, Object?>>? seed,
    Stream<DesktopEvent>? live,
  }) async {
    final fake = backend ?? FakeDesktopBackend();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore(seed),
          ),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          if (live != null)
            desktopEventStreamProvider.overrideWithValue(live),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: const DesktopApp(initialLocation: '/logs'),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopLogsPage)).l10n;

  /// The live card has its own search field and type picker, so a filter test has to name the card
  /// it means instead of matching text that appears twice on the page.
  Finder inTable(Finder matching) =>
      find.descendant(of: find.byType(LogQueryTable), matching: matching);
  Finder inLive(Finder matching) =>
      find.descendant(of: find.byType(LogLivePanel), matching: matching);

  /// The branch is taller than a window, so a control below the fold has to be scrolled to before
  /// it can be tapped.
  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('汇总与查询表都显示服务返回的数字', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopLogsPage), findsOneWidget);
    expect(find.text(l10n.logRequestsOverview), findsOneWidget);
    expect(find.text(l10n.desktopLogWindow24h), findsOneWidget);

    // The summary is the service's own aggregate, not a recount of the three rows below.
    expect(find.text('12,345'), findsWidgets);
    expect(find.text('987'), findsOneWidget);
    expect(find.text('8,000'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('12 ms'), findsOneWidget);
    expect(find.text('65%'), findsOneWidget);

    // Rows come from the log endpoint, newest first, with the trailing dot stripped.
    expect(find.text('example1.com'), findsOneWidget);
    expect(find.text('example2.com'), findsOneWidget);
    expect(find.text('laptop'), findsOneWidget);
    expect(find.text(l10n.statusBlocked), findsWidgets);
    expect(find.text(l10n.logRowCacheHit), findsOneWidget);

    // The table asked for one page of the log, not for the dashboard's little ring buffer.
    expect(backend.lastSearch['limit'], '25');
    expect(backend.lastSearch['offset'], '0');
    expect(backend.lastSearch['includeFile'], '1');
    expect(backend.has('/api/v1/querylog/stats'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索防抖之后才把域名条件发给服务', (tester) async {
    final backend = await pumpLogs(tester);
    final before = backend.searches.length;

    await tester.enterText(inTable(find.byType(TextField)).first, 'example2');
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.searches.length, before, reason: '每次按键都发请求会压垮服务端');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(backend.lastSearch['domain'], 'example2');
    expect(backend.lastSearch['offset'], '0');
  });

  testWidgets('客户端与记录类型各自作为独立条件发给服务', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(inTable(find.byType(TextField)).last, '192.168.1.20');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(backend.lastSearch['client'], '192.168.1.20');
    expect(backend.lastSearch.containsKey('domain'), isFalse);

    await tester.tap(inTable(find.text(l10n.desktopLogAllTypes)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CommonPopupMenu),
        matching: find.text('AAAA'),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.lastSearch['qtype'], 'AAAA');
    expect(backend.lastSearch['offset'], '0');

    await tester.tap(find.text(l10n.obsClearFilter));
    await tester.pumpAndSettle();
    expect(backend.lastSearch.containsKey('client'), isFalse);
    expect(backend.lastSearch.containsKey('qtype'), isFalse);
    expect(inTable(find.byType(TextField)), findsNWidgets(2));
    expect(
      tester.widget<TextField>(inTable(find.byType(TextField)).last).controller?.text,
      isEmpty,
    );
  });

  testWidgets('清空历史先确认，确认后请服务删除并重读', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);
    final searches = backend.searches.length;

    await tapAt(tester, inTable(find.text(l10n.desktopLogClear)));
    expect(find.text(l10n.desktopLogClearBody), findsOneWidget);
    // 取消不发出任何写请求。
    await tapAt(tester, find.text(l10n.configCancel));
    expect(backend.has('/api/v1/querylog/clear'), isFalse);

    await tapAt(tester, inTable(find.text(l10n.desktopLogClear)));
    await tapAt(
      tester,
      find.descendant(
        of: find.byType(CommonDialog),
        matching: find.text(l10n.desktopLogClear),
      ),
    );
    expect(backend.has('/api/v1/querylog/clear'), isTrue);
    // 服务把统计一并删了，所以表格与汇总都必须重读。
    expect(backend.searches.length, greaterThan(searches));
    expect(find.text(l10n.desktopLogClearDone), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('状态筛选把 status 发给服务，重置后不再带条件', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inTable(find.text(l10n.commonAll)));
    await tapAt(
      tester,
      find.descendant(
        of: find.byType(CommonPopupMenu),
        matching: find.text(l10n.logBlocked),
      ),
    );
    expect(backend.lastSearch['status'], 'blocked');

    await tapAt(tester, inTable(find.text(l10n.obsClearFilter)));
    expect(backend.lastSearch.containsKey('status'), isFalse);
  });

  testWidgets('三列排行按服务返回的顺序与计数展示', (tester) async {
    await pumpLogs(
      tester,
      backend: FakeDesktopBackend(
        queryStats: queryStatsPayload(
          topDomains: const [
            {'name': 'api.example.com', 'count': 321},
            {'name': 'cdn.example.com', 'count': 123},
          ],
          topBlocked: const [
            {'name': 'ads.example.com', 'count': 88},
          ],
          topClients: const [
            {'name': 'laptop', 'count': 45},
          ],
        ),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLogTopDomains), findsOneWidget);
    expect(find.text(l10n.desktopLogTopBlocked), findsOneWidget);
    expect(find.text(l10n.desktopLogTopClients), findsOneWidget);
    expect(find.text('api.example.com'), findsOneWidget);
    expect(find.text('321'), findsOneWidget);
    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    // 排行是服务算好的，页面不补也不截。
    expect(find.text(l10n.commonNoData), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排行无数据时分别说明无数据与无拦截', (tester) async {
    await pumpLogs(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.commonNoData), findsNWidgets(2));
    expect(find.text(l10n.desktopLogNoBlocked), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('汇总读不到时不画排行，只留一处离线提示', (tester) async {
    await pumpLogs(tester, backend: FakeDesktopBackend(statusCode: 500));
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLogTopDomains), findsNothing);
    expect(find.text(l10n.desktopBackendOfflineTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('翻页按 offset 请求，两端按钮随总数禁用', (tester) async {
    final backend = await pumpLogs(
      tester,
      backend: FakeDesktopBackend(
        queryLog: {...queryLogPayload(), 'total': 100},
      ),
    );
    final l10n = l10nOf(tester);

    // First page: nothing before it.
    expect(find.text(l10n.desktopLogPageInfo('1', '3', '100')), findsOneWidget);
    await tapAt(tester, find.text(l10n.desktopLogPagePrev));
    expect(backend.lastSearch['offset'], '0');

    await tapAt(tester, find.text(l10n.desktopLogPageNext));
    expect(backend.lastSearch['offset'], '25');
    expect(find.text(l10n.desktopLogPageInfo('26', '28', '100')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有记录时说没有记录，并藏起翻页', (tester) async {
    await pumpLogs(
      tester,
      backend: FakeDesktopBackend(
        queryLog: {'total': 0, 'entries': const <Object>[]},
      ),
    );
    final l10n = l10nOf(tester);

    expect(inTable(find.byType(NullStatus)), findsOneWidget);
    expect(find.text(l10n.logRecentRequestsEmpty), findsOneWidget);
    expect(find.text(l10n.desktopLogPageNext), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('读不到查询记录时给出重试，而不是一张空表', (tester) async {
    await pumpLogs(tester, backend: FakeDesktopBackend(statusCode: 500));
    final l10n = l10nOf(tester);

    expect(find.textContaining(l10n.obsLoadFailed), findsOneWidget);
    expect(find.text(l10n.logRecentRequestsEmpty), findsNothing);
    expect(find.text(l10n.desktopRetry), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('放大字号后不溢出，行高随文字增长', (tester) async {
    await pumpLogs(
      tester,
      size: const Size(390, 844),
      seed: {
        'diting_settings': {'app_text_scale': 1.4},
      },
    );

    expect(find.text('example1.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口收起时间与协议列，只留行本体', (tester) async {
    await pumpLogs(tester, size: const Size(390, 844));
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLogDomain), findsNothing);
    expect(find.text(l10n.obsProtocol), findsNothing);
    expect(find.text('example1.com'), findsOneWidget);
    expect(find.text(l10n.obsRecordsHeader), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  /// One pushed query, as the panel receives it. The wire format itself is pinned in
  /// `desktop_event_client_test.dart`; here only the list's behaviour matters.
  DesktopLiveQuery liveQueryOf({
    required String domain,
    String qtype = 'A',
    String clientIp = '192.168.1.20',
    String clientName = '',
    double durationMs = 4.5,
    bool success = true,
    String rcode = 'NOERROR',
    String cacheHit = '',
    bool blocked = false,
    String filterRule = '',
    int timestamp = 1700000000000,
  }) => DesktopLiveQuery.fromJson({
    'domain': domain,
    'qtype': qtype,
    'clientIP': clientIp,
    'clientName': clientName,
    'durationMs': durationMs,
    'success': success,
    'rcode': rcode,
    'cacheHit': cacheHit,
    'blocked': blocked,
    'filterRule': filterRule,
  }, timestamp: timestamp);

  testWidgets('推送的查询按新到旧进入实时列表', (tester) async {
    final live = StreamController<DesktopEvent>();
    addTearDown(live.close);
    await pumpLogs(tester, live: live.stream);
    final l10n = l10nOf(tester);

    // 还没有连接时不说自己在监听。
    expect(find.text(l10n.desktopLiveDisconnected), findsOneWidget);
    expect(find.text(l10n.desktopLiveEmpty), findsOneWidget);

    live.add(const DesktopChannelEvent(connected: true));
    live.add(
      DesktopQueryEvent(
        liveQueryOf(domain: 'first.example.com.', clientName: 'laptop'),
      ),
    );
    live.add(
      DesktopQueryEvent(
        liveQueryOf(
          domain: 'ads.example.com.',
          blocked: true,
          filterRule: '||ads.example.com^',
          timestamp: 1700000001000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.desktopLiveConnected), findsOneWidget);
    expect(find.text('first.example.com'), findsOneWidget);
    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.text('laptop (192.168.1.20)'), findsOneWidget);
    // 缓冲区计数是页面自己数的，标签说明它是缓冲区。
    expect(find.text(l10n.desktopLiveCaptured), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('暂停后不再收录，继续后恢复，清空只清缓冲', (tester) async {
    final live = StreamController<DesktopEvent>();
    addTearDown(live.close);
    await pumpLogs(tester, live: live.stream);
    final l10n = l10nOf(tester);

    void push(String domain) => live.add(
      DesktopQueryEvent(
        liveQueryOf(domain: '$domain.', clientIp: '127.0.0.1'),
      ),
    );

    push('kept.example.com');
    await tester.pumpAndSettle();
    expect(find.text('kept.example.com'), findsOneWidget);

    await tester.tap(find.text(l10n.desktopLivePause));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLivePaused), findsOneWidget);
    push('dropped.example.com');
    await tester.pumpAndSettle();
    expect(find.text('dropped.example.com'), findsNothing);

    await tester.tap(find.text(l10n.desktopLiveResume));
    await tester.pumpAndSettle();
    push('after.example.com');
    await tester.pumpAndSettle();
    expect(find.text('after.example.com'), findsOneWidget);

    await tester.tap(find.text(l10n.desktopLiveClear));
    await tester.pumpAndSettle();
    expect(find.text('kept.example.com'), findsNothing);
    expect(find.text(l10n.desktopLiveEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅看已拦截与记录类型筛选只影响实时列表的显示', (tester) async {
    final live = StreamController<DesktopEvent>();
    addTearDown(live.close);
    await pumpLogs(tester, live: live.stream);
    final l10n = l10nOf(tester);

    void push(String domain, {String qtype = 'A', bool blocked = false}) =>
        live.add(
          DesktopQueryEvent(
            liveQueryOf(
              domain: '$domain.',
              qtype: qtype,
              blocked: blocked,
              clientIp: '127.0.0.1',
            ),
          ),
        );

    push('plain.example.com');
    push('blocked.example.com', blocked: true);
    push('v6.example.com', qtype: 'AAAA');
    await tester.pumpAndSettle();
    expect(find.text('plain.example.com'), findsOneWidget);
    expect(find.text('v6.example.com'), findsOneWidget);

    await tester.tap(find.text(l10n.desktopLiveOnlyBlocked));
    await tester.pumpAndSettle();
    expect(find.text('plain.example.com'), findsNothing);
    expect(find.text('blocked.example.com'), findsOneWidget);

    await tester.tap(find.text(l10n.desktopLiveOnlyBlocked));
    await tester.pumpAndSettle();
    await tester.tap(inLive(find.text(l10n.desktopLogAllTypes)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CommonPopupMenu),
        matching: find.text('AAAA'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('v6.example.com'), findsOneWidget);
    expect(find.text('plain.example.com'), findsNothing);
    // 筛选只发生在缓冲区内，不去问服务端。
    expect(tester.takeException(), isNull);
  });

  testWidgets('通道断开后如实说明未连接', (tester) async {
    final live = StreamController<DesktopEvent>();
    addTearDown(live.close);
    await pumpLogs(tester, live: live.stream);
    final l10n = l10nOf(tester);

    live.add(const DesktopChannelEvent(connected: true));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLiveConnected), findsOneWidget);

    live.add(const DesktopChannelEvent(connected: false));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLiveDisconnected), findsOneWidget);
    expect(find.text(l10n.desktopLiveDisconnectedBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
