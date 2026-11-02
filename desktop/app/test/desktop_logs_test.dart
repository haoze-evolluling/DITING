// Desktop logs (desktop parity): the service's 24-hour summary and rankings on the dashboard, and
// the live query stream, the query log with the console's search conditions and offset paging, and
// the retention policy on the hub's query-log page. Every figure and row must come from the API; a failed read says so
// instead of showing an empty table, and a socket that is down says so instead of looking quiet.

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_event_client.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/home/desktop_home_page.dart';
import 'package:diting_desktop/pages/hub/desktop_query_log_page.dart';
import 'package:diting_desktop/pages/logs/widgets/log_config_card.dart';
import 'package:diting_desktop/pages/logs/widgets/log_live_panel.dart';
import 'package:diting_desktop/pages/logs/widgets/log_query_table.dart';
import 'package:diting_desktop/pages/logs/widgets/log_rankings_card.dart';
import 'package:diting_desktop/pages/logs/widgets/log_summary_card.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
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
    bool queryLog = true,
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
        child: DesktopApp(
          initialLocation: queryLog ? DesktopQueryLogPage.path : Routes.home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) {
    final page = find.byType(DesktopQueryLogPage);
    final target = page.evaluate().isEmpty
        ? find.byType(DesktopHomePage)
        : page;
    return tester.element(target).l10n;
  }

  /// The live card has its own search field and type picker, so a filter test has to name the card
  /// it means instead of matching text that appears twice on the page.
  Finder inTable(Finder matching) =>
      find.descendant(of: find.byType(LogQueryTable), matching: matching);
  Finder inLive(Finder matching) =>
      find.descendant(of: find.byType(LogLivePanel), matching: matching);

  /// The log cards only. Home also draws the dashboard and the device list, and both repeat
  /// figures the log section shows (a blocked count, a client named `laptop`).
  Finder inLogs(Finder matching) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is LogSummaryCard ||
          widget is LogRankingCard ||
          widget is LogLivePanel ||
          widget is LogQueryTable ||
          widget is LogConfigCard,
    ),
    matching: matching,
  );

  /// The table's own `/querylog/search` calls. The home page also reads this endpoint for its
  /// recent-queries card, so `lastSearch` may belong to that card instead.
  Map<String, String> lastTableSearch(FakeDesktopBackend backend) =>
      backend.searches.where((query) => query['includeFile'] == '1').last;

  /// The branch is taller than a window, so a control below the fold has to be scrolled to before
  /// it can be tapped.
  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('汇总与查询表都显示服务返回的数字', (tester) async {
    final backend = await pumpLogs(tester, queryLog: false);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopHomePage), findsOneWidget);
    expect(inLogs(find.text(l10n.logRequestsOverview)), findsOneWidget);
    expect(inLogs(find.text(l10n.desktopLogWindow24h)), findsOneWidget);

    // The summary is the service's own aggregate, not a recount of the three rows below.
    expect(inLogs(find.text('12,345')), findsWidgets);
    expect(inLogs(find.text('987')), findsOneWidget);
    expect(inLogs(find.text('8,000')), findsOneWidget);
    expect(inLogs(find.text('12')), findsOneWidget);
    expect(inLogs(find.text('12 ms')), findsOneWidget);
    expect(inLogs(find.text('65%')), findsOneWidget);

    expect(backend.has('/api/v1/querylog/stats'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('查询表在查询日志页显示服务返回的记录', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    // Rows come from the log endpoint, newest first, with the trailing dot stripped.
    expect(inTable(find.text('example1.com')), findsOneWidget);
    expect(inTable(find.text('example2.com')), findsOneWidget);
    expect(inTable(find.text('laptop')), findsOneWidget);
    expect(inTable(find.text(l10n.statusBlocked)), findsWidgets);
    expect(inTable(find.text(l10n.logRowCacheHit)), findsOneWidget);

    // The table asked for one page of the log, not for the dashboard's little ring buffer.
    expect(lastTableSearch(backend)['limit'], '25');
    expect(lastTableSearch(backend)['offset'], '0');
    expect(lastTableSearch(backend)['includeFile'], '1');
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
    expect(lastTableSearch(backend)['domain'], 'example2');
    expect(lastTableSearch(backend)['offset'], '0');
  });

  testWidgets('客户端与记录类型各自作为独立条件发给服务', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(inTable(find.byType(TextField)).last, '192.168.1.20');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(lastTableSearch(backend)['client'], '192.168.1.20');
    expect(lastTableSearch(backend).containsKey('domain'), isFalse);

    await tapAt(tester, inTable(find.text(l10n.desktopLogAllTypes)));
    await tapAt(
      tester,
      find.descendant(
        of: find.byType(CommonPopupMenu),
        matching: find.text('AAAA'),
      ),
    );
    expect(lastTableSearch(backend)['qtype'], 'AAAA');
    expect(lastTableSearch(backend)['offset'], '0');

    await tapAt(tester, find.text(l10n.obsClearFilter));
    expect(lastTableSearch(backend).containsKey('client'), isFalse);
    expect(lastTableSearch(backend).containsKey('qtype'), isFalse);
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
    expect(lastTableSearch(backend)['status'], 'blocked');

    await tapAt(tester, inTable(find.text(l10n.obsClearFilter)));
    expect(lastTableSearch(backend).containsKey('status'), isFalse);
  });

  testWidgets('三列排行按服务返回的顺序与计数展示', (tester) async {
    await pumpLogs(
      tester,
      queryLog: false,
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

    expect(inLogs(find.text(l10n.desktopLogTopDomains)), findsOneWidget);
    expect(inLogs(find.text(l10n.desktopLogTopBlocked)), findsOneWidget);
    expect(inLogs(find.text(l10n.desktopLogTopClients)), findsOneWidget);
    expect(inLogs(find.text('api.example.com')), findsOneWidget);
    expect(inLogs(find.text('321')), findsOneWidget);
    expect(inLogs(find.text('ads.example.com')), findsOneWidget);
    expect(inLogs(find.text('88')), findsOneWidget);
    expect(inLogs(find.text('45')), findsOneWidget);
    // 排行是服务算好的，页面不补也不截。
    expect(find.text(l10n.commonNoData), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排行无数据时分别说明无数据与无拦截', (tester) async {
    await pumpLogs(tester, queryLog: false);
    final l10n = l10nOf(tester);

    expect(inLogs(find.text(l10n.commonNoData)), findsNWidgets(2));
    expect(inLogs(find.text(l10n.desktopLogNoBlocked)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('汇总读不到时不画排行，只留一处离线提示', (tester) async {
    await pumpLogs(
      tester,
      queryLog: false,
      backend: FakeDesktopBackend()
        ..failingPaths.add('/api/v1/querylog/stats'),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLogTopDomains), findsNothing);
    expect(inLogs(find.text(l10n.desktopBackendOfflineTitle)), findsOneWidget);
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
    expect(lastTableSearch(backend)['offset'], '0');

    await tapAt(tester, find.text(l10n.desktopLogPageNext));
    expect(lastTableSearch(backend)['offset'], '25');
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
    await pumpLogs(
      tester,
      backend: FakeDesktopBackend()
        ..failingPaths.add('/api/v1/querylog/search'),
    );
    final l10n = l10nOf(tester);

    expect(inTable(find.textContaining(l10n.obsLoadFailed)), findsOneWidget);
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

    expect(inTable(find.text('example1.com')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口收起时间与协议列，只留行本体', (tester) async {
    await pumpLogs(tester, size: const Size(390, 844));
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLogDomain), findsNothing);
    expect(find.text(l10n.obsProtocol), findsNothing);
    expect(inTable(find.text('example1.com')), findsOneWidget);
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

    await tapAt(tester, find.text(l10n.desktopLivePause));
    expect(find.text(l10n.desktopLivePaused), findsOneWidget);
    push('dropped.example.com');
    await tester.pumpAndSettle();
    expect(find.text('dropped.example.com'), findsNothing);

    await tapAt(tester, find.text(l10n.desktopLiveResume));
    push('after.example.com');
    await tester.pumpAndSettle();
    expect(find.text('after.example.com'), findsOneWidget);

    await tapAt(tester, find.text(l10n.desktopLiveClear));
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

    await tapAt(tester, find.text(l10n.desktopLiveOnlyBlocked));
    expect(find.text('plain.example.com'), findsNothing);
    expect(find.text('blocked.example.com'), findsOneWidget);

    await tapAt(tester, find.text(l10n.desktopLiveOnlyBlocked));
    await tapAt(tester, inLive(find.text(l10n.desktopLogAllTypes)));
    await tapAt(
      tester,
      find.descendant(
        of: find.byType(CommonPopupMenu),
        matching: find.text('AAAA'),
      ),
    );
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

  testWidgets('留存策略展示服务返回的开关、数字与落盘目录', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    expect(backend.has('/api/v1/querylog/config'), isTrue);
    expect(find.text(l10n.desktopLogConfigTitle), findsOneWidget);
    expect(find.text(l10n.desktopLogConfigEnabled), findsOneWidget);
    expect(find.text(l10n.desktopLogConfigFile), findsOneWidget);
    expect(find.text(l10n.desktopLogConfigClients), findsOneWidget);
    expect(find.text('10000'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(
      find.text(l10n.desktopLogConfigDataDir(r'C:\ProgramData\DITING\logs')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭查询日志后立即提交，落盘开关随之隐藏', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text(l10n.desktopLogConfigEnabled));
    expect(backend.configUpdates.single['enabled'], isFalse);
    expect(find.text(l10n.desktopLogConfigFile), findsNothing);
    expect(find.text(l10n.desktopLogConfigSaved), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开关被服务拒绝时回到原值并说明原因', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);
    // 只让写操作失败：读仍然正常，否则连配置都读不到。
    backend.rejectWrites = true;

    await tapAt(tester, find.text(l10n.desktopLogConfigClients));
    // 卡片内保留失败原因，同时弹一次提示。
    expect(find.textContaining(l10n.desktopActionFailed('')), findsWidgets);
    // 开关保持服务端当前值，页面不假装已生效。
    expect(find.text(l10n.desktopLogConfigFile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('缓冲条数与留存天数由保存按钮提交，非法值不提交', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    // 首页同时画着限流卡，它也有数字输入框，所以这里只说留存策略卡里的那两个。
    final numbers = find.descendant(
      of: find.byType(LogConfigCard),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(numbers.first);
    await tester.enterText(numbers.first, '');
    await tester.pumpAndSettle();
    await tapAt(tester, find.byTooltip(l10n.desktopLogConfigSave));
    expect(find.text(l10n.desktopLogConfigInvalid), findsOneWidget);
    expect(backend.configUpdates, isEmpty, reason: '空值不该发给服务');

    await tester.enterText(numbers.first, '20000');
    await tester.enterText(numbers.last, '14');
    await tester.pumpAndSettle();
    await tapAt(tester, find.byTooltip(l10n.desktopLogConfigSave));

    final update = backend.configUpdates.last;
    expect(update['maxEntries'], 20000);
    expect(update['retentionDays'], 14);
    expect(update['enabled'], isTrue, reason: '其余字段原样带上');
    expect(update.containsKey('dataDir'), isFalse, reason: '落盘目录由服务拥有');
    expect(tester.takeException(), isNull);
  });

  testWidgets('读不到留存策略时说明原因并给重试', (tester) async {
    await pumpLogs(
      tester,
      backend: FakeDesktopBackend()
        ..failingPaths.add('/api/v1/querylog/config'),
    );
    final l10n = l10nOf(tester);

    expect(
      find.textContaining(l10n.desktopLogConfigLoadFailed),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopLogConfigEnabled), findsNothing);
    expect(find.text(l10n.desktopRetry), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
