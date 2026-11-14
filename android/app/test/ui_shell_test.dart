// Whole-app smoke test of `DitingApp`: scopes above `Navigator`, tab state, route
// building and the Android page transition.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:diting_android/pages/about/about_page.dart';
import 'package:diting_android/pages/home/dashboard/cards/network_speed_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/traffic_monitor_card.dart';
import 'package:diting_android/pages/home/dashboard/dashboard_board.dart';
import 'package:diting_android/pages/home/dashboard/detail/network_speed_detail_page.dart';
import 'package:diting_android/pages/home/widgets/home_power_button.dart';
import 'package:diting_android/pages/hub/feature_hub_page.dart';
import 'package:diting_android/pages/settings/settings_page.dart';
import 'package:diting_android/pages/system/unknown_route_page.dart';
import 'package:diting_android/pages/tools/tools_page.dart';
import 'package:diting_android/pages/traffic/traffic_page.dart';
import 'package:diting_android/router.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_vpn_controller.dart';
import 'support/test_hooks.dart';

void main() {
  group('外壳与底栏', _appShell);
  group('路由可达性', _routeCatalog);
  group('二级页转场', _routeTransition);
  group('功能中心可见性', _featureHub);
}

/// Whole-app smoke test of `DitingApp`: scopes above `Navigator`, tab state, route building
void _appShell() {
  installGlobalTestHooks();

  Future<void> pumpApp(
    WidgetTester tester, {
    String? initialLocation,
    FakeVpnController? vpn,
    List<BottomBarDestination>? dock,
    Size size = const Size(1170, 2532),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          if (vpn != null) vpnControllerProvider.overrideWithValue(vpn),
          if (dock != null) bottomBarProvider.overrideWith(() => _Dock(dock)),
        ],
        child: DitingApp(initialLocation: initialLocation),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('电源按钮经历启动中并回到运行态', (tester) async {
    final fake = FakeVpnController(delay: const Duration(milliseconds: 200))
      ..statusValue = const VpnStatus(running: true, persisted: true);
    await pumpApp(tester, vpn: fake);
    await tester.tap(find.byType(HomePowerButton));
    await tester.pump();
    expect(find.byType(CommonCircleLoading), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(CommonCircleLoading), findsNothing);
    expect(find.bySemanticsLabel('停止'), findsOneWidget);
  });

  testWidgets('底栏切页后 branch 保留状态', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('功能中心'));
    await tester.pumpAndSettle();
    // Assert category headings: card titles collide with bottom-bar labels
    expect(
      find.descendant(
        of: find.byType(FeatureHubPage),
        matching: find.text(_featureCategories.first.title),
      ),
      findsWidgets,
    );
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('谛听 · 普通'), findsOneWidget);
  });

  testWidgets('切换 tab 期间新旧两页同时在场', (tester) async {
    await pumpApp(tester);
    // Home is the only branch on stage before the switch.
    expect(find.byType(DashboardBoard), findsOneWidget);
    expect(find.byType(FeatureHubPage), findsNothing);

    await tester.tap(find.text('功能中心'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    // Mid-transition the leaving page has not vanished yet: both branches are
    // on stage, which is what makes the switch a real slide instead of an entry
    // fade on a single page.
    expect(find.byType(FeatureHubPage), findsOneWidget);
    expect(find.byType(DashboardBoard), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(FeatureHubPage), findsOneWidget);
    expect(find.byType(DashboardBoard), findsNothing);
  });

  testWidgets('切换界面语言后功能中心文案立即跟随', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('功能中心'));
    await tester.pumpAndSettle();
    expect(find.text('DNS 解析'), findsWidgets);

    // Regression: the categories were cached in a provider that only watched the work mode and
    // the hidden set, so the hub kept the previous language until the app restarted.
    ProviderScope.containerOf(tester.element(find.byType(FeatureHubPage)))
        .read(languageModeProvider.notifier)
        .select(AppLanguageMode.english);
    await tester.pumpAndSettle();

    expect(find.text('DNS resolution'), findsWidgets);
    expect(find.text('DNS resolvers'), findsWidgets);
    expect(find.text('DNS 解析'), findsNothing);
  });

  testWidgets('浮层（面板）在 scopes 之上可弹出', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('解析服务商'));
    await tester.pumpAndSettle();
    expect(find.text('选择解析服务商'), findsOneWidget);
    await tester.tap(find.text('腾讯云 DNSPod').first);
    await tester.pumpAndSettle();
    expect(find.text('选择解析服务商'), findsNothing);
  });

  testWidgets('浮条高度不截断页面的滚动视口', (tester) async {
    await pumpApp(tester, initialLocation: Routes.settings);
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final list = find.descendant(
      of: find.byType(PageBody),
      matching: find.byType(ListView),
    );
    // `SafeArea` would pad the dock inset into the scroll view; `DockSpacer` gives way instead
    expect(tester.getRect(list).bottom, screenHeight);
  });

  testWidgets('系统手势区不会让浮条多让一次位', (tester) async {
    // A 48px (16dp) gesture inset: the dock folds it into its own margin, so an extra `SafeArea`
    // would lift the bar by another inset and spend the reserved gap on that padding instead,
    // leaving content resting against the glass.
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    await pumpApp(tester, initialLocation: Routes.settings);
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final dock = find.byType(NavigationDock);
    final inset = NavigationDock.insetOf(tester.element(dock));
    // Hugs the edge, and the glass sits exactly `inset` minus the gap above the bottom margin
    expect(tester.getRect(dock).bottom, screenHeight);
    expect(
      tester.getRect(find.byType(FloatingNavigationBar)).top,
      screenHeight - (inset - dockContentGap),
    );
  });

  testWidgets('备用底栏的自带 SafeArea 不会吃掉预留间隙', (tester) async {
    // Five items force the plain `NavigationBar`, whose own `SafeArea` pads the gesture inset.
    // The reserve must count that inset too, otherwise the bar swallows the clearance above it.
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    await pumpApp(
      tester,
      initialLocation: Routes.settings,
      dock: const [
        BottomBarDestination.home,
        BottomBarDestination.featureHub,
        BottomBarDestination.logDashboard,
        BottomBarDestination.appTraffic,
        BottomBarDestination.settings,
      ],
    );
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(find.byType(NavigationBar), findsOneWidget);
    final reserve = DockInsetScope.of(
      tester.element(find.byType(PageBody).first),
    );
    final barTop = tester.getRect(find.byType(NavigationBar)).top;
    // Bottom of the reserved band minus the bar top is the clearance content gets
    expect(barTop - (screenHeight - reserve), moreOrLessEquals(dockContentGap));
  });

  testWidgets('订阅页读真实表：无旧库时是空状态而不是 mock 订阅', (tester) async {
    await pumpApp(tester, initialLocation: Routes.subscriptions);
    // No 1.4.3 database on the test host, so the page renders its empty state
    expect(find.text('AdGuard 基础'), findsNothing);
    expect(find.text('EasyList China'), findsNothing);
    expect(find.text('还没有订阅'), findsOneWidget);
    expect(find.textContaining('解析并写入规则库'), findsWidgets);
    expect(find.textContaining('后续版本接入'), findsNothing);
  });

  group('底栏点击落到正确的 tab', () {
    // Regression: the bar reports destination indices, `goBranch` wants branch indices
    const userDock = [
      BottomBarDestination.home,
      BottomBarDestination.featureHub,
      BottomBarDestination.networkTools,
      BottomBarDestination.settings,
    ];

    testWidgets('四个底栏项各自打开自己的页面', (tester) async {
      await pumpApp(tester, dock: userDock);
      const expectations = {
        '功能中心': FeatureHubPage,
        '网络工具': ToolsPage,
        '设置': SettingsPage,
      };
      for (final entry in expectations.entries) {
        await tester.tap(find.text(entry.key).last);
        await tester.pumpAndSettle();
        expect(
          find.byType(entry.value),
          findsOneWidget,
          reason: '点「${entry.key}」应打开 ${entry.value}',
        );
      }
    });

    // Regression: hub entries pointing at other tabs' roots clone the shell
    // Entering a tab page from the feature hub opens it standalone: no dock, and a way back.
    testWidgets('功能中心里指向其它 tab 的卡片以全屏页打开并给出返回键', (tester) async {
      await pumpApp(tester, initialLocation: Routes.hub, dock: userDock);
      final card = find.text('网络诊断');
      await tester.scrollUntilVisible(
        card,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(ToolsPage), findsOneWidget);
      expect(find.byType(NavigationDock), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDock), findsOneWidget);
      expect(find.byType(ToolsPage), findsNothing);
      expect(find.text('功能中心'), findsWidgets);
    });

    testWidgets('首页网络速度卡进入网速详情后可返回并切回其它 tab', (tester) async {
      await pumpApp(tester, dock: userDock);
      final detail = find.descendant(
        of: find.byType(NetworkSpeedCard),
        matching: find.byTooltip('详情'),
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(detail);
      await tester.pumpAndSettle();
      expect(find.byType(NetworkSpeedDetailPage), findsOneWidget);
      expect(find.byType(TrafficPage), findsNothing);
      expect(find.byType(NavigationDock), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkSpeedDetailPage), findsNothing);
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    // Regression: the alert is pushed on the root navigator while the page sits on a branch
    // navigator; popping the page's own navigator removed the page and left a black screen.
    testWidgets('分支页面的清除弹窗取消后仍停留在流量统计', (tester) async {
      await pumpApp(tester, initialLocation: Routes.traffic, dock: userDock);
      await tester.tap(find.byTooltip('清除历史'));
      await tester.pumpAndSettle();
      expect(find.text('清除全部流量记录？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('清除全部流量记录？'), findsNothing);
      expect(find.byType(TrafficPage), findsOneWidget);
      expect(find.byType(NavigationDock), findsOneWidget);
    });

    // Regression: the logs dashboard used to switch to the traffic branch, which kept the bar
    // and left no way back; it now opens the full-screen twin like the hub card does.
    testWidgets('日志仪表盘的流量监控以全屏页打开并给出返回键', (tester) async {
      await pumpApp(tester, initialLocation: Routes.logs, dock: userDock);
      // The monitor sits below the fold; tap its own detail button, not the first one on the page.
      final detail = find.descendant(
        of: find.byType(TrafficMonitorCard),
        matching: find.byTooltip('详情'),
      );
      await tester.ensureVisible(detail);
      await tester.pumpAndSettle();
      await tester.tap(detail);
      await tester.pumpAndSettle();
      expect(find.byType(TrafficPage), findsOneWidget);
      expect(find.byType(NavigationDock), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(TrafficPage), findsNothing);
      expect(find.byType(NavigationDock), findsOneWidget);
    });

    // Regression: a page outside the bar must report -1, not light up "home"
    testWidgets('日志仪表盘编辑模式可移除卡片，完成后卡片不再显示', (tester) async {
      await pumpApp(tester, initialLocation: Routes.logs, dock: userDock);
      expect(find.text('请求日志仪表盘'), findsOneWidget);
      await tester.tap(find.byTooltip('编辑仪表盘'));
      await tester.pumpAndSettle();
      // The hero is the first card; its remove badge is the first one.
      await tester.tap(find.byType(DashboardRemoveBadge).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('请求日志仪表盘'), findsNothing);
      expect(find.text('流量监控'), findsOneWidget);
    });

    // Regression: a page outside the bar must report -1, not light up "home"
    testWidgets('当前页不在底栏里时底栏不点亮任何一项', (tester) async {
      await pumpApp(tester, initialLocation: Routes.traffic, dock: userDock);
      final dock = tester.widget<NavigationDock>(find.byType(NavigationDock));
      expect(dock.selectedIndex, -1);
    });

    testWidgets('宽屏备用底栏也不点亮任何一项', (tester) async {
      // Wide windows replace the floating dock with the plain `NavigationBar`, which has no
      // "nothing selected" state; clamping the index to 0 used to light up 首页 on `/traffic`.
      await pumpApp(
        tester,
        initialLocation: Routes.traffic,
        dock: userDock,
        size: const Size(3840, 2400),
      );
      expect(find.byType(NavigationDock), findsNothing);
      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget);
      final theme = tester.widget<NavigationBarTheme>(
        find.ancestor(of: bar, matching: find.byType(NavigationBarTheme)).first,
      );
      final scheme = Theme.of(tester.element(bar)).colorScheme;
      const selected = {WidgetState.selected};
      expect(theme.data.indicatorColor, Colors.transparent);
      expect(
        theme.data.iconTheme?.resolve(selected)?.color,
        scheme.onSurfaceVariant,
      );
      expect(
        theme.data.labelTextStyle?.resolve(selected)?.color,
        scheme.onSurfaceVariant,
      );
    });
  });
}

class _Dock extends BottomBarNotifier {
  _Dock(this._dock);

  final List<BottomBarDestination> _dock;

  @override
  List<BottomBarDestination> build() => _dock;
}

/// Guards that every hub card points at a registered route; per-route layout and fallback are
/// covered by `layout_regression_test.dart`, which pumps the same catalogue at three sizes
void _routeCatalog() {
  installGlobalTestHooks();

  Future<void> pumpAt(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: appTestOverrides(),
        child: DitingApp(initialLocation: location),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Asserts the mounted page neither threw nor landed on the fallback page.
  void expectReached(WidgetTester tester, String route, String label) {
    expect(tester.takeException(), isNull, reason: '$label ($route) 构建抛异常');
    expect(
      find.byType(UnknownRoutePage),
      findsNothing,
      reason: '$label ($route) 没有注册：落到了未知路由兜底页',
    );
  }

  group('功能中心卡片可达', () {
    testWidgets('每张卡片的 route 都能构建', (tester) async {
      // Deduplicate: several entries can point at the same page.
      final routes = <String>{
        for (final category in _featureCategories)
          for (final card in category.cards) card.route,
      };
      expect(routes, isNotEmpty);

      for (final route in routes) {
        await pumpAt(tester, route);
        expectReached(tester, route, '功能中心卡片');
      }
    });
  });

  group('兜底页', () {
    testWidgets('未注册的路径落到 UnknownRoutePage', (tester) async {
      await pumpAt(tester, '/definitely/not/a/route');
      expect(find.byType(UnknownRoutePage), findsOneWidget);
      expect(find.text('/definitely/not/a/route'), findsOneWidget);
    });
  });
}

/// Guards second-level pages are full-screen pages that carry FlClash's card transition.
void _routeTransition() {
  installGlobalTestHooks();

  testWidgets('二级页 push 出来的是带转场的全屏页', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: appTestOverrides(), child: const DitingApp()),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(NavigationDock).first))
        .push(Routes.about);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Mid-transition: `/about` is mounted but not yet in place.
    expect(find.byType(AboutPage), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(AboutPage)));
    expect(route, isNotNull);
    expect(
      route!.transitionDuration,
      greaterThan(Duration.zero),
      reason: '没有转场时长 = go_router 退化成 `NoTransitionPage`，页面是硬切的',
    );

    // Still moving: animation below 1 and the position differs from the final one.
    expect(route.animation!.value, lessThan(1.0));
    final midX = tester.getTopLeft(find.byType(AboutPage)).dx;
    await tester.pumpAndSettle();
    final settledX = tester.getTopLeft(find.byType(AboutPage)).dx;
    expect(
      midX,
      isNot(closeTo(settledX, 0.5)),
      reason: '转场期间页面的横向位置必须和落位后不同，否则动画没生效',
    );
    expect(route.animation!.value, 1.0);

    expect(
      find.byWidgetPredicate((widget) => widget is NoTransitionPage),
      findsNothing,
      reason:
          '路由用了 `builder:` 而不是 `pageBuilder`：go_router 的 '
          '`isMaterialApp` 认不出 material_ui 的 MaterialApp，会退化成无转场页',
    );
  });
}

/// Guards feature-hub visibility: hidden cards drop their category, fixed cards stay
final _zh = lookupAppL10n(const Locale('zh'));
final _featureCategories = mockFeatureCategories(_zh);

void _featureHub() {
  test('隐藏卡片后分类为空时整类消失，固定卡始终保留', () {
    final hidden = {
      for (final card in _featureCategories.first.cards)
        if (card.featureKey != null) card.featureKey!,
    };
    final categories = visibleFeatureCategories(
      express: false,
      hiddenKeys: hidden,
      l10n: _zh,
    );
    expect(categories.any((category) => category.title == 'DNS 解析'), isFalse);
    expect(categories.length, _featureCategories.length - 1);

    final allHidden = {
      for (final card in _featureCategories.expand(
        (category) => category.cards,
      ))
        if (card.featureKey != null) card.featureKey!,
    };
    final onlyFixed = visibleFeatureCategories(
      express: false,
      hiddenKeys: allHidden,
      l10n: _zh,
    );
    expect(onlyFixed.length, 1);
    expect(onlyFixed.single.cards.single.title, '隐藏功能');
  });
}
