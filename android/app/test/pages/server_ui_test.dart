import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/server/server_client.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/home/home_page.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_server_client.dart';
import '../support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  Future<void> pumpServer(
    WidgetTester tester,
    String route, {
    ServerClient? client,
    Size size = const Size(412, 915),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(serverClient: client),
          workModeProvider.overrideWith(_ServerMode.new),
        ],
        child: DitingApp(initialLocation: route),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Finder card(String title) => find
      .ancestor(of: find.text(title), matching: find.byType(AnimatedScale))
      .first;

  testWidgets('配置中心按解析服务、规则与日志、系统分组并保持双列卡片宽度', (tester) async {
    await pumpServer(tester, ServerRoutes.hub);

    expect(find.text('配置中心'), findsOneWidget);
    expect(find.text('解析服务'), findsOneWidget);
    expect(find.text('规则与日志'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
    for (final title in [
      '服务商',
      '调度与缓存',
      'Bootstrap 摘要',
      '服务器设置',
      '拦截规则',
      '查询日志',
      '外观',
      '关于',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺少配置入口 $title');
    }
    expect(find.text('订阅管理'), findsNothing);
    expect(find.text('规则测试'), findsNothing);
    expect(find.text('2 个上游'), findsOneWidget);
    expect(find.text('3 个服务器'), findsOneWidget);
    expect(find.textContaining('保留 7 天'), findsOneWidget);

    final providers = tester.getTopLeft(card('服务商'));
    final upstream = tester.getTopLeft(card('调度与缓存'));
    final bootstrap = tester.getTopLeft(card('Bootstrap 摘要'));
    final settings = tester.getTopLeft(card('服务器设置'));
    expect(upstream.dx, greaterThan(providers.dx));
    expect(upstream.dy, closeTo(providers.dy, 0.5));
    expect(bootstrap.dx, closeTo(providers.dx, 0.5));
    expect(bootstrap.dy, greaterThan(providers.dy));
    expect(settings.dx, closeTo(upstream.dx, 0.5));
    expect(settings.dy, closeTo(bootstrap.dy, 0.5));

    final rules = tester.getRect(card('拦截规则'));
    final log = tester.getRect(card('查询日志'));
    expect(log.left, greaterThan(rules.left));
    expect(log.top, closeTo(rules.top, 0.5));
    expect(log.width, closeTo(rules.width, 0.5));
    expect(
      rules.width,
      closeTo(tester.getRect(card('服务商')).width, 0.5),
    );

    final appearance = tester.getRect(card('外观'));
    final about = tester.getRect(card('关于'));
    expect(about.left, greaterThan(appearance.left));
    expect(about.top, closeTo(appearance.top, 0.5));
    expect(about.width, closeTo(appearance.width, 0.5));
  });

  testWidgets('调度与缓存页面按用途分组展示设置卡片', (tester) async {
    await pumpServer(tester, ServerRoutes.upstream);

    expect(find.text('调度方式'), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('缓存设置'), findsOneWidget);
    expect(find.textContaining('4096 条 · 最大 TTL 3600s'), findsOneWidget);
    expect(find.text('最大条目'), findsNothing);
    expect(find.text('TTL 模式'), findsNothing);
    expect(find.text('预取'), findsNothing);
    expect(find.text('最小 TTL 值'), findsNothing);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('缓存设置'),
      280,
      scrollable: scrollable,
    );
    await tester.tap(find.text('缓存设置'));
    await tester.pumpAndSettle();

    expect(find.text('缓存设置'), findsOneWidget);
    expect(find.text('缓存容量'), findsOneWidget);
    expect(find.text('最小 TTL 值'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('预取'),
      280,
      scrollable: scrollable,
    );
    expect(find.text('预取'), findsOneWidget);
  });

  testWidgets('日志域名搜索防抖 300ms，客户端筛选独立生效', (tester) async {
    final client = _LogFake();
    await pumpServer(tester, ServerRoutes.logs, client: client);
    final initialCalls = client.queries.length;

    await tester.enterText(find.byType(SearchField), 'ads.example.com');
    await tester.pump(const Duration(milliseconds: 299));
    expect(client.queries.length, initialCalls, reason: '防抖期间不应发起新查询');

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(client.queries.last.domain, 'ads.example.com');

    await tester.tap(find.byTooltip('筛选客户端'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tablet').last);
    await tester.pumpAndSettle();
    expect(client.queries.last.client, 'tablet');

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedControl<String>),
        matching: find.text('已拦截'),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.queries.last.status, 'blocked');
  });

  testWidgets('自定义规则保存到服务器配置', (tester) async {
    final client = _LogFake();
    await pumpServer(tester, ServerRoutes.filterRules, client: client);

    await tester.enterText(
      find.byType(TextField),
      '||ads.example.com^\n0.0.0.0 tracker.example',
    );
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    final saved = await client.getConfig();
    expect(saved.filter.customRules, [
      '||ads.example.com^',
      '0.0.0.0 tracker.example',
    ]);
  });

  testWidgets('自定义规则有未保存更改时拦截返回', (tester) async {
    await pumpServer(tester, ServerRoutes.filter);

    await tester.tap(find.text('自定义规则'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '||draft.example^');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('保存更改？'), findsOneWidget);
    await tester.tap(find.text('不保存'));
    await tester.pumpAndSettle();
    expect(find.text('拦截设置'), findsOneWidget);
  });

  testWidgets('缓存设置二级页面可切换预取', (tester) async {
    final client = FakeServerClient();
    await pumpServer(tester, ServerRoutes.upstreamAdvanced, client: client);

    await tester.scrollUntilVisible(
      find.text('预取'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('预取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预取'));
    await tester.pumpAndSettle();

    final saved = await client.getConfig();
    expect(saved.cache.prefetchEnabled, isTrue);
  });

  testWidgets('调度与缓存页面可进入缓存设置二级页面', (tester) async {
    await pumpServer(tester, ServerRoutes.upstream);

    await tester.scrollUntilVisible(
      find.text('缓存设置'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('缓存设置'));
    await tester.pumpAndSettle();

    expect(find.text('缓存容量'), findsOneWidget);
    expect(find.text('最小 TTL'), findsOneWidget);
    expect(find.text('最小 TTL 值'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('最小 TTL 值')).dx,
      tester.getTopLeft(find.text('最小 TTL')).dx,
      reason: '从属数值行应与父行标题左对齐',
    );
    await tester.scrollUntilVisible(
      find.text('乐观缓存'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('乐观缓存'), findsOneWidget);
  });

  testWidgets('缓存 TTL 模式通过弹出菜单切换', (tester) async {
    final client = _LogFake();
    await pumpServer(tester, ServerRoutes.upstreamAdvanced, client: client);

    await tester.scrollUntilVisible(
      find.text('限制最大 TTL'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('限制最大 TTL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('固定 TTL'));
    await tester.pumpAndSettle();

    final saved = await client.getConfig();
    expect(saved.cache.mode, 'fixed');
  });

  testWidgets('过滤拦截方式通过弹出菜单切换', (tester) async {
    final client = _LogFake();
    await pumpServer(tester, ServerRoutes.filter, client: client);

    await tester.tap(find.text('返回空地址'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回 NXDOMAIN'));
    await tester.pumpAndSettle();

    final saved = await client.getConfig();
    expect(saved.filter.blockMode, 'nxdomain');
  });

  testWidgets('日志保留天数通过弹出菜单切换', (tester) async {
    final client = _LogFake();
    await pumpServer(tester, ServerRoutes.queryLog, client: client);

    await tester.tap(find.text('7 天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 天'));
    await tester.pumpAndSettle();

    final saved = await client.getConfig();
    expect(saved.queryLog.retentionDays, 30);
  });

  testWidgets('服务器首页展示运行状态与快捷入口', (tester) async {
    final client = FakeServerClient(
      status: ServerStatus(
        running: true,
        root: false,
        port: 1053,
        addresses: const ['192.168.1.23:1053'],
        startedAt: DateTime.now().subtract(const Duration(minutes: 75)),
      ),
      stats: const ServerStats(
        queries: 1200,
        blocked: 240,
        cached: 600,
        forwarded: 960,
        averageResponseMs: 8,
        blockedRate: 0.2,
        cacheHitRate: 0.5,
      ),
    );
    await pumpServer(tester, ServerRoutes.root, client: client);

    expect(find.text('谛听 · DNS 服务'), findsOneWidget);
    expect(find.text('运行状态'), findsOneWidget);
    expect(find.text('正在监听'), findsOneWidget);
    expect(find.text('快捷操作'), findsOneWidget);
    expect(find.text('请求概览'), findsOneWidget);

    await tester.tap(find.text('调度与缓存'));
    await tester.pumpAndSettle();
    expect(find.text('当前调度'), findsOneWidget);
  });

  testWidgets('调度与缓存页面内联切换调度方式', (tester) async {
    final client = FakeServerClient();
    await pumpServer(tester, ServerRoutes.upstream, client: client);

    expect(find.text('当前调度'), findsOneWidget);
    await tester.tap(find.text('主备切换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('并行竞速'));
    await tester.pumpAndSettle();

    final saved = await client.getConfig();
    expect(saved.upstream.mode, 'parallel_race');
    expect(find.text('并行竞速'), findsOneWidget);
  });

  testWidgets('服务商预设按服务器协议写入配置', (tester) async {
    final client = FakeServerClient();
    await pumpServer(tester, ServerRoutes.upstreamProviders, client: client);

    await tester.tap(find.byTooltip('添加服务商'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchField), '101.226.4.6');
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(of: find.text('360'), matching: find.byType(ListItem)),
    );
    await tester.pumpAndSettle();

    final saved = await client.getConfig();
    expect(saved.upstream.providers, hasLength(3));
    expect(saved.upstream.providers.last.protocol, 'PLAIN');
    expect(saved.upstream.providers.last.server, '101.226.4.6:53');
  });

  testWidgets('Bootstrap 预设直接写入服务器配置', (tester) async {
    final client = FakeServerClient();
    await pumpServer(tester, ServerRoutes.upstreamBootstrap, client: client);

    await tester.tap(find.text('阿里云'));
    await tester.pumpAndSettle();

    final saved = await client.getConfig();
    expect(
      saved.upstream.bootstrap.map((entry) => entry.id),
      isNot(contains('preset_alidns')),
    );
  });

  for (final (modeLabel, homeTitle) in [
    ('普通模式', '谛听 · 普通'),
    ('简洁模式', '谛听 · 简洁'),
  ]) {
    testWidgets('服务器模式切到$modeLabel后离开服务器路由', (tester) async {
      await pumpServer(tester, ServerRoutes.root);

      await tester.tap(find.byTooltip('切换工作模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(modeLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text(homeTitle), findsOneWidget);
    });
  }

  testWidgets('服务器首页展示流量、拦截、缓存与排行卡片', (tester) async {
    final client = FakeServerClient(
      status: const ServerStatus(
        running: true,
        root: false,
        port: 1053,
        addresses: ['192.168.1.23:1053'],
      ),
      stats: ServerStats(
        queries: 12840,
        blocked: 3180,
        cached: 6120,
        forwarded: 6620,
        averageResponseMs: 8.4,
        blockedRate: 3180 / 12840,
        cacheHitRate: 6120 / 12840,
        perHour: [
          for (var hour = 0; hour < 24; hour++)
            ServerHourPoint(
              hour: DateTime(2026, 11, 19, hour),
              queries: 180 + (hour * 37) % 560,
              blocked: 30 + (hour * 11) % 130,
              cached: 80 + (hour * 23) % 300,
            ),
        ],
        topDomains: const [ServerNameCount(name: 'www.baidu.com', count: 1820)],
        topClients: const [ServerNameCount(name: 'MacBook Pro', count: 4300)],
      ),
    );
    await pumpServer(tester, ServerRoutes.root, client: client);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('解析流量'),
      320,
      scrollable: scrollable,
    );
    expect(find.text('峰值'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('拦截分析'),
      320,
      scrollable: scrollable,
    );
    expect(find.text('拦截分析'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('缓存效率'),
      320,
      scrollable: scrollable,
    );
    expect(find.text('缓存效率'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('热门域名'),
      320,
      scrollable: scrollable,
    );
    expect(find.text('www.baidu.com'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('活跃客户端'),
      320,
      scrollable: scrollable,
    );
    expect(find.text('MacBook Pro'), findsOneWidget);
  });

  testWidgets('清空查询日志弹窗的取消与清空按钮关闭弹窗且停留在日志页', (tester) async {
    final client = _LogFake();
    await pumpServer(tester, ServerRoutes.logs, client: client);

    await tester.tap(find.byTooltip('清空'));
    await tester.pumpAndSettle();
    expect(find.text('清空查询日志'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('清空查询日志'), findsNothing);
    expect(find.byType(SearchField), findsOneWidget);

    await tester.tap(find.byTooltip('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '清空'));
    await tester.pumpAndSettle();

    expect(find.text('清空查询日志'), findsNothing);
    expect(find.byType(SearchField), findsOneWidget);
    expect(client.clearCalls, 1);
  });

  testWidgets('服务停止时仍可查看历史日志', (tester) async {
    final client = _LogFake(status: const ServerStatus());
    await pumpServer(tester, ServerRoutes.logs, client: client);

    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.text('服务器未运行'), findsNothing);
  });

  testWidgets('服务停止时规则测试仍可使用', (tester) async {
    final client = FakeServerClient();
    await pumpServer(tester, ServerRoutes.filterTest, client: client);

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.tap(find.text('测试'));
    await tester.pumpAndSettle();

    expect(find.text('将被放行'), findsOneWidget);
  });
}

class _LogFake extends FakeServerClient {
  _LogFake({ServerStatus? status})
    : super(
        status:
            status ??
            const ServerStatus(
              running: true,
              root: false,
              port: 1053,
              addresses: ['0.0.0.0:1053'],
            ),
        stats: const ServerStats(
          queries: 3,
          blocked: 1,
          topClients: [ServerNameCount(name: 'tablet', count: 2)],
        ),
      );

  final queries = <ServerLogQuery>[];
  int clearCalls = 0;

  @override
  Future<void> clearQueryLog() async {
    clearCalls++;
  }

  @override
  Future<ServerQueryResult> queryLog(ServerLogQuery query) async {
    queries.add(query);
    final record = ServerQueryRecord(
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      domain: 'ads.example.com',
      qtype: 'A',
      clientName: 'tablet',
      status: 'blocked',
      blocked: true,
      upstreamProvider: 'AliDNS',
      durationMs: 3,
    );
    return ServerQueryResult(total: 1, entries: [record]);
  }
}

class _ServerMode extends WorkModeNotifier {
  @override
  AppWorkMode build() => AppWorkMode.server;
}
