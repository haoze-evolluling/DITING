// Settings that used to reset on restart: appearance, dashboard order and the two
// config-resource tables.

import 'dart:convert';

import 'package:diting_shared/app/theme/layout.dart';
import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_android/data/log_dashboard_widgets.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_android/data/prefs/config_resource_store.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:diting_android/pages/config/on_demand_capabilities.dart';
import 'package:diting_android/pages/hub/provider_visibility_page.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_android/state/log_dashboard_layout_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/site_latency_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

void main() {
  group('重新打开后仍在', _settingsPersistence);
  group('自定义资源表', _configResources);
}

/// Settings that used to reset on restart: appearance, dashboard order, on-demand matching and the
/// user agent every client sends.
void _settingsPersistence() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryLegacyPrefsStore store;

  setUp(() => store = MemoryLegacyPrefsStore());

  ProviderContainer container() {
    final instance = ProviderContainer(
      overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(instance.dispose);
    return instance;
  }

  group('外观设置重新打开后仍在', () {
    test('纯黑主题', () {
      container().read(pureBlackProvider.notifier).toggle(true);
      expect(store.read('dns_vpn_prefs', 'pure_black_theme'), isTrue);
      expect(container().read(pureBlackProvider), isTrue);
    });

    test('字号按布局上限钳位后再落盘', () {
      final notifier = container().read(textScaleProvider.notifier);
      notifier.set(3);
      expect(store.read('dns_vpn_prefs', 'app_text_scale'), maxTextScale);
      expect(container().read(textScaleProvider), maxTextScale);

      notifier.set(0.1);
      expect(container().read(textScaleProvider), minTextScale);
    });

    test('字体族空值表示跟随系统', () {
      final notifier = container().read(selectedFontFamilyProvider.notifier);
      notifier.select('Noto Sans SC');
      expect(store.read('dns_vpn_prefs', 'app_font_family'), 'Noto Sans SC');
      expect(container().read(selectedFontFamilyProvider), 'Noto Sans SC');

      notifier.select(null);
      expect(container().read(selectedFontFamilyProvider), isNull);
    });
  });

  group('看板卡片顺序重新打开后仍在', () {
    test('没有落盘时用默认布局', () {
      expect(
        container().read(dashboardWidgetsProvider),
        defaultDashboardWidgets,
      );
    });

    test('增删与移动都会写回', () {
      final notifier = container().read(dashboardWidgetsProvider.notifier);
      notifier.remove(DashboardWidget.status);
      expect(
        container().read(dashboardWidgetsProvider),
        isNot(contains(DashboardWidget.status)),
      );
      expect(store.read('dns_vpn_prefs', 'dashboard_widget_order'), isNotNull);

      notifier.add(DashboardWidget.status);
      notifier.move(0, 1);
      final reopened = container().read(dashboardWidgetsProvider);
      expect(reopened.first, isNot(DashboardWidget.status));
      expect(reopened, contains(DashboardWidget.status));
    });

    test('旧版布局升级时补上搬到看板的两张卡', () {
      store.putString(
        'dns_vpn_prefs',
        'dashboard_widget_order',
        '["status","networkSpeed"]',
      );
      final layout = container().read(dashboardWidgetsProvider);
      expect(layout.take(2), [
        DashboardWidget.provider,
        DashboardWidget.resolution,
      ]);
      expect(
        layout,
        containsAll([DashboardWidget.status, DashboardWidget.networkSpeed]),
      );
      // Migrated once: reopening reads the same board instead of inserting again.
      expect(container().read(dashboardWidgetsProvider), layout);
    });

    test('坏 JSON 回落到默认布局', () {
      store.putString('dns_vpn_prefs', 'dashboard_widget_order', '{not json');
      expect(
        container().read(dashboardWidgetsProvider),
        defaultDashboardWidgets,
      );
    });
  });

  group('日志仪表盘按日志模式各自保存布局', () {
    test('没有落盘时用该模式的默认卡片', () {
      for (final mode in LegacyLogMode.values) {
        expect(
          container().read(logDashboardWidgetsProvider(mode)),
          logDashboardCatalogOf(mode),
        );
      }
    });

    test('改一个模式不影响另一个，重新打开后仍在', () {
      container()
          .read(logDashboardWidgetsProvider(LegacyLogMode.all).notifier)
          .remove(LogDashboardWidget.hero);
      final reopened = container();
      expect(
        reopened.read(logDashboardWidgetsProvider(LegacyLogMode.all)),
        isNot(contains(LogDashboardWidget.hero)),
      );
      expect(
        reopened.read(logDashboardWidgetsProvider(LegacyLogMode.off)),
        contains(LogDashboardWidget.hero),
      );
    });

    test('不属于该模式的卡片读取时跳过、也加不进去', () {
      store.putString(
        'dns_vpn_prefs',
        'log_dashboard_widget_order_off',
        '["trafficMonitor","privacyMode"]',
      );
      final instance = container();
      final provider = logDashboardWidgetsProvider(LegacyLogMode.off);
      expect(instance.read(provider), [LogDashboardWidget.privacyMode]);
      instance.read(provider.notifier).add(LogDashboardWidget.trafficMonitor);
      expect(instance.read(provider), [LogDashboardWidget.privacyMode]);
    });

    test('隐藏 AI 卡时拖动排序不丢失它的位置', () {
      final instance = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          agentKeyConfiguredProvider.overrideWithValue(false),
        ],
      );
      addTearDown(instance.dispose);
      // The AI card sits mid-board in this mode, so a reorder must leave its slot alone.
      const mode = LegacyLogMode.all;
      final visible = instance.read(visibleLogDashboardWidgetsProvider(mode));
      expect(visible, isNot(contains(LogDashboardWidget.aiInsight)));
      // Move the hero (visible index 0) below the stats card.
      instance
          .read(logDashboardWidgetsProvider(mode).notifier)
          .moveVisible(visible, 0, 1);
      expect(instance.read(logDashboardWidgetsProvider(mode)), [
        LogDashboardWidget.stats,
        LogDashboardWidget.hero,
        LogDashboardWidget.recentRequests,
        LogDashboardWidget.trafficStructure,
        LogDashboardWidget.ruleBlocks,
        LogDashboardWidget.aiInsight,
        LogDashboardWidget.trafficMonitor,
        LogDashboardWidget.requestOverview,
        LogDashboardWidget.cacheHotspots,
        LogDashboardWidget.raceWinners,
        LogDashboardWidget.bootstrapDns,
      ]);
    });
  });

  group('仪表盘站点选择重新打开后仍在', () {
    test('没有落盘时用默认四站', () {
      expect(
        container().read(dashboardSiteIdsProvider),
        defaultDashboardSiteIds,
      );
      expect(
        container().read(dashboardSitesProvider).length,
        dashboardSiteCount,
      );
    });

    test('勾选与取消都会写回，且最多四个', () {
      final notifier = container().read(dashboardSiteIdsProvider.notifier);
      // The default four already fill the card, so a new site needs a free slot first.
      expect(notifier.toggle('baidu'), isTrue);
      expect(
        container().read(dashboardSiteIdsProvider),
        isNot(contains('baidu')),
      );

      expect(notifier.toggle('github'), isTrue);
      expect(
        store.read('dns_vpn_prefs', 'dashboard_site_ids'),
        allOf(contains('github'), isNotNull),
      );
      expect(container().read(dashboardSitesProvider).last.id, 'github');

      notifier.reset();
      expect(
        container().read(dashboardSiteIdsProvider),
        defaultDashboardSiteIds,
      );
    });

    test('未知 id 从不认识的站点被丢弃', () {
      store.putString(
        'dns_vpn_prefs',
        'dashboard_site_ids',
        '["github","no_such_site","steam"]',
      );
      final sites = container().read(dashboardSitesProvider);
      expect(sites.map((target) => target.id), ['github', 'steam']);
    });
  });

  group('按需连接判定用的是真实 SSID', () {
    test('页面 provider 读的是已落盘的白名单', () {
      final notifier = container().read(configResourcesProvider.notifier);
      notifier.setOnDemand(true);
      notifier.putSsid(
        null,
        const MockSsidRule(ssid: 'Cafe', cellular: false, wifi: true),
      );
      final decision = container().read(onDemandDecisionProvider);
      // No platform channel in tests, so the SSID is unknown rather than fabricated.
      expect(decision.state, SsidMatchState.unknown);
    });
  });

  group('User-Agent 是所有请求共用的真实值', () {
    test('没选时用兜底值', () {
      expect(container().read(requestUserAgentProvider), appFallbackUserAgent);
      expect(resolveRequestUserAgent('  '), appFallbackUserAgent);
    });

    test('选中后 provider 跟着变', () {
      final notifier = container().read(configResourcesProvider.notifier);
      notifier.addUserAgent('MyAgent/1.0');
      notifier.selectUserAgent('MyAgent/1.0');
      expect(container().read(requestUserAgentProvider), 'MyAgent/1.0');

      notifier.selectUserAgent(null);
      expect(container().read(requestUserAgentProvider), appFallbackUserAgent);
    });
  });

  group('服务显示页不再把设置抄到本地', () {
    Future<void> pumpPage(WidgetTester tester, ProviderContainer c) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const AppHost(child: ProviderVisibilityPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('切换后立即刷新并落盘', (tester) async {
      await pumpPage(tester, container());

      await tester.tap(find.text('全部 DNS 服务'));
      await tester.pumpAndSettle();

      expect(find.text('不显示该类型的服务'), findsOneWidget);
      expect(
        store.read('dns_vpn_prefs', 'home_visible_protocols'),
        isNot(contains('DNS')),
      );
    });

    testWidgets('外部改写（如导入备份）后不需要重进就同步', (tester) async {
      final c = container();
      await pumpPage(tester, c);

      c
          .read(legacySettingsProvider)
          .setHomeProviderVisibility(
            visibleProtocols: const {'DOH', 'DOT'},
            hiddenProviderIds: const {},
            visibleProviderIds: const {},
          );
      c.read(legacySettingsRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();

      expect(find.text('不显示该类型的服务'), findsOneWidget);
    });
  });
}

/// Pins the two config-resource tables, which used to live in memory and reverted on restart
void _configResources() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryLegacyPrefsStore store;

  setUp(() => store = MemoryLegacyPrefsStore());

  ProviderContainer container() {
    final instance = ProviderContainer(
      overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(instance.dispose);
    return instance;
  }

  group('写入后能在新容器里读回', () {
    test('User-Agent 与选中项', () {
      final notifier = container().read(configResourcesProvider.notifier);
      expect(notifier.addUserAgent('MyAgent/1.0'), isTrue);
      notifier.selectUserAgent('MyAgent/1.0');

      final reopened = container().read(configResourcesProvider);
      expect(reopened.userAgents.map((a) => a.value), contains('MyAgent/1.0'));
      expect(reopened.selectedUserAgent, 'MyAgent/1.0');
    });

    test('SSID 规则增删改与开关', () {
      final notifier = container().read(configResourcesProvider.notifier);
      expect(
        notifier.putSsid(
          null,
          const MockSsidRule(ssid: 'Cafe', delayMs: 1200, cellular: false),
        ),
        isTrue,
      );
      notifier.toggleSsid('Cafe', wifi: false);

      final reopened = container().read(configResourcesProvider);
      final rule = reopened.ssidRules.firstWhere((r) => r.ssid == 'Cafe');
      expect(rule.delayMs, 1200);
      expect(rule.wifi, isFalse);
      expect(rule.cellular, isFalse);
    });

    test('按需连接开关', () {
      container().read(configResourcesProvider.notifier).setOnDemand(true);
      expect(container().read(configResourcesProvider).onDemand, isTrue);
    });

    test('删光 UA 列表后不会回落到演示值', () {
      final notifier = container().read(configResourcesProvider.notifier);
      for (final agent in mockUserAgents) {
        if (!agent.isDefault) notifier.removeUserAgent(agent.value);
      }
      notifier.addUserAgent('Only/1.0');
      notifier.removeUserAgent('Only/1.0');

      final reopened = container().read(configResourcesProvider);
      expect(reopened.userAgents, hasLength(1));
      expect(reopened.userAgents.single.isDefault, isTrue);
    });
  });

  group('损坏数据', () {
    test('坏 JSON 回落到初始值而不是崩溃', () {
      store.putString(
        ConfigResourceStore.container,
        'user_agents_json',
        '{not json',
      );
      final state = container().read(configResourcesProvider);
      expect(state.userAgents, hasLength(mockUserAgents.length));
    });

    test('一组坏掉不牵连另外一组', () {
      store.putString(
        ConfigResourceStore.container,
        'user_agents_json',
        'oops',
      );
      store.putString(
        ConfigResourceStore.container,
        'ssid_rules_json',
        jsonEncode([
          {'ssid': 'Kept', 'cellular': true, 'wifi': true, 'delayMs': 0},
        ]),
      );
      final state = container().read(configResourcesProvider);
      expect(state.userAgents, hasLength(mockUserAgents.length));
      expect(state.ssidRules, hasLength(1));
      expect(state.ssidRules.single.ssid, 'Kept');
    });
  });
}
