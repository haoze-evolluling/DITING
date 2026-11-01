// Desktop log branch (docs/development/flutter-desktop-ui.md step 4): the service's 24-hour
// summary and its query log, with search, one status filter and offset paging. Every figure and
// row must come from the API; a failed read says so instead of showing an empty table.

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/pages/logs/desktop_logs_page.dart';
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

    await tester.enterText(find.byType(TextField), 'example2');
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.searches.length, before, reason: '每次按键都发请求会压垮服务端');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(backend.lastSearch['domain'], 'example2');
    expect(backend.lastSearch['offset'], '0');
  });

  testWidgets('状态筛选把 status 发给服务，重置后不再带条件', (tester) async {
    final backend = await pumpLogs(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.text(l10n.commonAll));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CommonPopupMenu),
        matching: find.text(l10n.logBlocked),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.lastSearch['status'], 'blocked');

    await tester.tap(find.text(l10n.obsClearFilter));
    await tester.pumpAndSettle();
    expect(backend.lastSearch.containsKey('status'), isFalse);
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
    await tester.tap(find.text(l10n.desktopLogPagePrev));
    await tester.pumpAndSettle();
    expect(backend.lastSearch['offset'], '0');

    await tester.tap(find.text(l10n.desktopLogPageNext));
    await tester.pumpAndSettle();
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

    expect(find.byType(NullStatus), findsOneWidget);
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
}
