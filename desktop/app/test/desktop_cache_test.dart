// Desktop hub cache page (desktop parity): the console's
// acceleration engine, telemetry, top names, policy form, persistence, exclude rules and the
// cached-entry table. Every figure must come from the service; a save posts the whole config and
// re-reads it, and a rejected write is reported instead of assumed.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/pages/hub/desktop_cache_page.dart';
import 'package:diting_desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_overview_cards.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_entries_card.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_config_card.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_fallback_card.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_persist_card.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_snapshot_card.dart';
import 'package:diting_desktop/widgets/masonry_grid.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';
import 'support/desktop_page_harness.dart';

void main() {
  Future<FakeDesktopBackend> pumpCache(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) => pumpDesktopPage(
    tester,
    path: DesktopCachePage.path,
    backend: backend,
    size: size,
  );

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopCachePage)).l10n;

  Finder inEngine(Finder matching) =>
      find.descendant(of: find.byType(CacheEngineCard), matching: matching);
  Finder inPersist(Finder matching) =>
      find.descendant(of: find.byType(CachePersistCard), matching: matching);
  Finder inSnapshot(Finder matching) =>
      find.descendant(of: find.byType(CacheSnapshotCard), matching: matching);
  Finder inConfig(Finder matching) =>
      find.descendant(of: find.byType(CacheConfigCard), matching: matching);
  Finder inFallback(Finder matching) =>
      find.descendant(of: find.byType(CacheFallbackCard), matching: matching);
  Finder inEntries(Finder matching) =>
      find.descendant(of: find.byType(CacheEntriesCard), matching: matching);

  /// The page is taller than a window, so a control below the fold has to be scrolled to first.

  /// Lets the current snackbar expire, so the next action's message is the one on screen.

  test('缺字段按零值解析，落盘间隔回落到服务默认值', () {
    final stats = DesktopCacheStats.fromJson(const {});
    expect(stats.hits, 0);
    expect(stats.fill, 0, reason: '容量未知时不能把条形画满');

    final config = DesktopCacheConfig.fromJson(const {
      'mode': 'fixed_ttl',
      'persistIntervalSeconds': 0,
    });
    expect(config.mode, 'fixed_ttl');
    expect(
      config.effectivePersistIntervalSeconds,
      desktopCacheDefaultPersistSeconds,
    );
    expect(DesktopCacheConfig.fromJson(const {}).mode, 'limit_max_ttl');

    final entry = DesktopCacheEntry.fromJson(const {'status': 'stale'});
    expect(entry.isStale, isTrue);
    expect(entry.ipList, isEmpty);
  });

  testWidgets('页面显示服务返回的命中率、遥测与排行', (tester) async {
    await pumpCache(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopCachePage), findsOneWidget);
    expect(find.text(l10n.desktopCacheHitRatio), findsOneWidget);
    expect(find.text('67%'), findsWidgets, reason: '0.6667 由服务给出');
    expect(
      find.text(l10n.desktopCacheTelemetryCapacity(640, 4096)),
      findsOneWidget,
    );
    expect(find.text('8,000'), findsOneWidget);
    expect(find.text('4,000'), findsOneWidget);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('example.com.'), findsWidgets);
    expect(find.text(l10n.desktopCacheTopHits(42)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换加速开关提交整份配置并回显服务端值', (tester) async {
    final backend = await pumpCache(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inEngine(find.byType(DashboardSwitch)));

    final update = backend.cacheConfigUpdates.single;
    expect(update['enabled'], isFalse);
    expect(update['mode'], 'limit_max_ttl', reason: '整份配置原样带上');
    expect(update['excludePatterns'], isEmpty);
    expect(find.text(l10n.desktopCacheEngineOff), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('策略秒数由保存按钮提交，非法值不提交', (tester) async {
    final backend = await pumpCache(tester);
    final l10n = l10nOf(tester);

    // 策略卡片只提交 TTL 上下限：回退与预取的秒数各有自己的卡片和按钮。
    final numbers = inConfig(find.byType(TextFormField));
    await tester.ensureVisible(numbers.first);
    await tester.enterText(numbers.first, '');
    await tester.pumpAndSettle();
    await tapAt(tester, find.byTooltip(l10n.desktopCacheConfigSave));
    expect(find.text(l10n.desktopCacheInvalidNumbers), findsOneWidget);
    expect(backend.cacheConfigUpdates, isEmpty, reason: '空值不该发给服务');

    await tester.enterText(numbers.first, '900');
    await tester.enterText(numbers.at(1), '90');
    await tester.pumpAndSettle();
    await tapAt(tester, find.byTooltip(l10n.desktopCacheConfigSave));

    final update = backend.cacheConfigUpdates.last;
    expect(update['maxTtlSeconds'], 900);
    expect(update['minTtlSeconds'], 90);
    expect(update['staleFallbackSeconds'], 300, reason: '未编辑的项原样带上');
    expect(update['prefetchEnabled'], isFalse, reason: '未开启的项原样带上');
    await clearMessages(tester);

    final stale = inFallback(find.byType(TextFormField));
    await tester.enterText(stale.first, '240');
    await tester.pumpAndSettle();
    await tapAt(tester, inFallback(find.text(l10n.commonSave)));
    expect(backend.cacheConfigUpdates.last['staleFallbackSeconds'], 240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检索把关键字发给服务，状态筛选只收窄已返回的条目', (tester) async {
    final backend = await pumpCache(tester);
    final l10n = l10nOf(tester);

    expect(inEntries(find.text('example.com.')), findsOneWidget);
    expect(inEntries(find.text('missing.example.org.')), findsOneWidget);

    await tester.enterText(inEntries(find.byType(TextField)), 'example.net');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(backend.cacheQueries.last['query'], 'example.net');
    expect(backend.cacheQueries.last['limit'], '100');
    final requests = backend.cacheQueries.length;

    await tapAt(
      tester,
      inEntries(find.text(l10n.desktopCacheFilterNegative)).first,
    );
    expect(backend.cacheQueries, hasLength(requests), reason: '筛选只作用于已返回的条目');
    expect(inEntries(find.text('missing.example.org.')), findsOneWidget);
    expect(inEntries(find.text('example.com.')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('清空缓存先确认，确认后重新读取条目', (tester) async {
    final backend = await pumpCache(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inEngine(find.text(l10n.desktopCacheClear)));
    expect(find.text(l10n.desktopCacheClearTitle), findsOneWidget);
    await tapAt(tester, inDialog(find.text(l10n.desktopCacheClear)));

    expect(backend.cacheClears, 1);
    expect(find.text(l10n.desktopCacheClearDone), findsOneWidget);
    expect(inEntries(find.text(l10n.desktopCacheEntriesNone)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('落盘开关与间隔提交到服务，恢复操作先确认', (tester) async {
    final backend = await pumpCache(tester);
    final l10n = l10nOf(tester);

    // 未开启时两个手动操作不可用，路径也不显示。
    expect(inPersist(find.text(l10n.desktopCachePersistPath)), findsNothing);

    await tapAt(tester, inPersist(find.byType(DashboardSwitch)));
    expect(backend.cacheConfigUpdates.last['persistEnabled'], isTrue);
    expect(find.text(l10n.desktopCachePersistToggleOn), findsOneWidget);
    await clearMessages(tester);

    final interval = inPersist(find.byType(TextFormField));
    await tester.enterText(interval, '5');
    await tester.pumpAndSettle();
    await tapAt(tester, inPersist(find.text(l10n.commonSave)));
    expect(
      backend.cacheConfigUpdates.last['persistIntervalSeconds'],
      30,
      reason: '低于下限按 30 提交',
    );
    await clearMessages(tester);

    await tapAt(tester, inSnapshot(find.text(l10n.desktopCachePersistLoad)));
    expect(find.text(l10n.desktopCachePersistLoadTitle), findsOneWidget);
    await tapAt(tester, inDialog(find.text(l10n.desktopCachePersistLoad)));
    expect(backend.cacheLoads, 1);
    expect(find.text(l10n.desktopCachePersistLoadDone(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排除规则保存为一行一条的正则', (tester) async {
    final backend = await pumpCache(tester);
    final l10n = l10nOf(tester);

    final editor = find.byType(TextFormField).last;
    await tester.ensureVisible(editor);
    await tester.enterText(editor, [r'\.local$', '', r'^time\.'].join('\n'));
    await tester.pumpAndSettle();
    await tapAt(tester, find.byTooltip(l10n.desktopCacheExcludeSave));

    final patterns =
        backend.cacheConfigUpdates.last['excludePatterns'] as List<Object?>;
    expect(patterns, [r'\.local$', r'^time\.'], reason: '空行被丢弃');
    expect(find.text(l10n.desktopCacheExcludeSaved(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务拒绝写入时说明原因并保留原表单', (tester) async {
    final backend = await pumpCache(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tapAt(tester, inPersist(find.byType(DashboardSwitch)));

    expect(find.textContaining(l10n.desktopCacheSaveFailed('')), findsWidgets);
    expect(find.text(l10n.desktopCachePersistOff), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('需要令牌时整页说明原因并给重试', (tester) async {
    await pumpCache(tester, backend: FakeDesktopBackend(statusCode: 401));
    final l10n = l10nOf(tester);

    expect(find.byType(NullStatus), findsOneWidget);
    expect(find.text(l10n.desktopCacheLoadFailed), findsOneWidget);
    expect(find.text(l10n.desktopBackendUnauthorizedBody), findsOneWidget);
    expect(find.text(l10n.desktopRetry), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽窗全部卡片按双列瀑布流铺开，没有卡片跨两列', (tester) async {
    await pumpCache(tester);
    expect(find.byType(MasonryGrid), findsOneWidget);
    final cards = find.byType(DashboardCard).evaluate().toList();
    expect(cards, hasLength(10));
    final boxes = [
      for (final element in cards) element.renderObject! as RenderBox,
    ];
    final widths = boxes.map((box) => box.size.width).toSet();
    expect(widths, hasLength(1), reason: '所有卡片应等宽，不能有卡片跨两列');
    final lefts = boxes.map((box) => box.localToGlobal(Offset.zero).dx).toSet();
    expect(lefts, hasLength(2));
    expect(tester.takeException(), isNull);

    await pumpCache(tester, size: const Size(900, 900));
    expect(find.byType(MasonryGrid), findsNothing);
    expect(find.byType(DashboardCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口下明细表收起初始 TTL 与地址列', (tester) async {
    await pumpCache(tester, size: const Size(720, 900));
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopCacheEntryDomain), findsOneWidget);
    expect(find.text(l10n.desktopCacheEntryTtl), findsNothing);
    expect(find.text(l10n.desktopCacheEntryIps), findsNothing);
    expect(inEntries(find.text('example.com.')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('功能中心入口打开缓存子页', (tester) async {
    await pumpDesktopPage(tester, path: Routes.hub);
    final l10n = tester.element(find.byType(DesktopFeatureHubPage)).l10n;

    await tapAt(tester, find.text(l10n.desktopHubCache));

    expect(find.byType(DesktopCachePage), findsOneWidget);
    expect(find.text(l10n.desktopCacheEngineTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
