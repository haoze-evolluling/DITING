// Regression coverage for the legacy-compatibility cleanup: superseded values are no longer
// adapted or migrated, while malformed/missing data degrades safely to the current defaults.

import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/data/log_dashboard_widgets.dart';
import 'package:diting_android/state/dashboard_layout_providers.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_android/state/log_dashboard_layout_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerWith(MemoryLegacyPrefsStore store) {
    final container = ProviderContainer(
      overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('IPv6 旧落盘拼写不再适配', () {
    test('enabled / disabled 按未知值回退 auto，当前拼写仍可读', () {
      expect(LegacyIpv6Mode.fromStorageValue('enabled'), LegacyIpv6Mode.auto);
      expect(LegacyIpv6Mode.fromStorageValue('disabled'), LegacyIpv6Mode.auto);
      expect(LegacyIpv6Mode.fromStorageValue('ENABLED'), LegacyIpv6Mode.auto);
      expect(LegacyIpv6Mode.fromStorageValue('prefer'), LegacyIpv6Mode.prefer);
      expect(
        LegacyIpv6Mode.fromStorageValue('disable'),
        LegacyIpv6Mode.disable,
      );
      expect(LegacyIpv6Mode.fromStorageValue(null), LegacyIpv6Mode.auto);
      expect(LegacyIpv6Mode.fromStorageValue('  '), LegacyIpv6Mode.auto);
    });
  });

  group('首页看板：新旧数据混杂与异常', () {
    test('缺键使用当前默认布局', () {
      final container = containerWith(MemoryLegacyPrefsStore());
      expect(container.read(dashboardWidgetsProvider), defaultDashboardWidgets);
    });

    test('旧布局含未知/重复项时按当前卡片集过滤，不补插新版卡片', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'dashboard_widget_order':
              '["status","removed_card","status","networkSpeed"]',
        },
      });
      final container = containerWith(store);
      expect(container.read(dashboardWidgetsProvider), [
        DashboardWidget.status,
        DashboardWidget.networkSpeed,
      ]);
    });

    test('坏 JSON 回落默认布局', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {'dashboard_widget_order': '{not json'},
      });
      expect(
        containerWith(store).read(dashboardWidgetsProvider),
        defaultDashboardWidgets,
      );
    });

    test('空数组表示用户主动清空，保持为空', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {'dashboard_widget_order': '[]'},
      });
      expect(containerWith(store).read(dashboardWidgetsProvider), isEmpty);
    });
  });

  group('日志看板：旧顺序不再被升级重置', () {
    test('已存旧顺序原样保留，未知卡片被跳过', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'log_dashboard_widget_order_all': '["hero","obsolete","stats"]',
        },
      });
      final container = containerWith(store);
      expect(container.read(logDashboardWidgetsProvider(LegacyLogMode.all)), [
        LogDashboardWidget.hero,
        LogDashboardWidget.stats,
      ]);
    });
  });

  group('AI 服务商：旧平铺键不再迁移', () {
    test('仅有旧平铺键时生成无密钥示例，而不是迁移旧配置', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'agent_api_key': 'sk-legacy',
          'agent_api_base_url': 'https://legacy.example/v1',
          'agent_api_model': 'legacy-model',
        },
      });
      final state = loadAgentApiState(LegacySettings(store));
      expect(state.providers, hasLength(1));
      expect(state.providers.single.id, 'example');
      expect(state.providers.single.hasKey, isFalse);
    });

    test('损坏的服务商 JSON 回落到示例', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {'agent_ai_providers_json': '{not json'},
      });
      final state = loadAgentApiState(LegacySettings(store));
      expect(state.providers.single.id, 'example');
    });

    test('合法的服务商 JSON 被原样读取，不注入示例', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'agent_ai_providers_json':
              '[{"id":"p1","name":"P1","baseUrl":"https://x.test/v1",'
              '"modelName":"m","apiKey":""}]',
        },
      });
      final state = loadAgentApiState(LegacySettings(store));
      expect(state.providers.map((provider) => provider.id), ['p1']);
    });
  });

  group('缺失与异常设置回落当前默认', () {
    test('空存储读到当前默认值', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      expect(settings.bottomBarIds, LegacySettings.defaultBottomBarIds);
      expect(settings.resolutionModeRaw, 'single');
      expect(settings.workModeRaw, 'normal');
      expect(settings.serverPort, LegacySettings.defaultServerPort);
      expect(settings.appAllowlistRules, isEmpty);
    });

    test('坏 JSON 的集合类设置回落默认而不是抛异常', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'bottom_bar_destinations': '{bad',
          'app_allowlist_rules_json': '[1,2,3]',
          'custom_background_uris': 'oops',
        },
      });
      final settings = LegacySettings(store);
      expect(settings.bottomBarIds, LegacySettings.defaultBottomBarIds);
      expect(settings.appAllowlistRules, isEmpty);
      expect(settings.customBackgroundUris, isEmpty);
    });
  });
}
