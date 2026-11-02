// The tunnel state machine: power transitions, the express channel, the startup
// watchdog, on-demand SSID matching and the engine counters the native side reports.

import 'dart:convert';

import 'package:diting_android/data/db/rule_providers.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/server/dns_server_bridge.dart';
import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:diting_android/pages/config/on_demand_capabilities.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/on_demand_runner.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_vpn_controller.dart';

part 'tunnel_state_test_on_demand.dart';

void main() {
  group('启动看门狗', _powerGuard);
  group('极速模式', _expressMode);
  group('引擎计数', _engineStats);
  group('按需连接', _onDemand);
}

void _powerGuard() {
  test('未收到授权回调时不会永远停在启动中', () {
    fakeAsync((async) {
      // prepared: false -> the system shows the auth prompt, answered by MainActivity.
      final controller = FakeVpnController(prepared: false);
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {'app_work_mode': 'normal'},
      });
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(controller),
          ruleRepositoryProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);

      c.read(powerProvider.notifier).toggle();
      async.flushMicrotasks();
      expect(c.read(powerProvider), PowerState.starting);

      // A lost callback (activity recreated) must converge, or the power key stays dead.
      async.elapse(const Duration(seconds: 95));
      expect(c.read(powerProvider), PowerState.error);
      expect(c.read(powerProvider.notifier).lastError, '没有获得 VPN 授权');
      expect(c.read(legacySettingsProvider).vpnRunning, isFalse);

      // The error state allows another tap.
      expect(c.read(powerProvider).isBusy, isFalse);
    });
  });

  test('残留运行标志且原生状态不回应时收敛为失败', () {
    fakeAsync((async) {
      final controller = FakeVpnController(prepared: true)
        ..statusValue = const VpnStatus(running: false, persisted: true);
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {'app_work_mode': 'normal'},
        'dns_vpn_prefs': {'vpn_running': true},
      });
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(controller),
          ruleRepositoryProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(powerProvider), PowerState.starting);
      async.elapse(const Duration(seconds: 1));
      // Native says it is not running: settle on stopped instead of error.
      expect(c.read(powerProvider), PowerState.stopped);
      expect(c.read(legacySettingsProvider).vpnRunning, isFalse);
    });
  });

  test('开启启动时自动开启后，残留运行标志会重新拉起隧道', () {
    fakeAsync((async) {
      final controller = FakeVpnController(prepared: true)
        ..statusValue = const VpnStatus(running: false, persisted: true);
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {'app_work_mode': 'normal'},
        'dns_vpn_prefs': {
          'vpn_running': true,
          'auto_start_on_launch_enabled': true,
          'initial_agreement_accepted': true,
        },
      });
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(controller),
          ruleRepositoryProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);

      c.read(powerProvider);
      // Before the 700 ms follow-up sync, which would read the fake's fixed "not running".
      async.flushMicrotasks();
      expect(controller.startCalls, 1);
      expect(c.read(powerProvider), PowerState.running);
      expect(c.read(legacySettingsProvider).vpnRunning, isTrue);
    });
  });

  test('原生正在等待通道释放时不重复启动', () {
    fakeAsync((async) {
      final controller = FakeVpnController(prepared: true)
        ..statusValue = const VpnStatus(
          running: false,
          persisted: true,
          reclaiming: true,
        );
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {'app_work_mode': 'normal'},
        'dns_vpn_prefs': {
          'vpn_running': true,
          'auto_start_on_launch_enabled': true,
          'initial_agreement_accepted': true,
        },
      });
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(controller),
          ruleRepositoryProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);

      c.read(powerProvider);
      async.elapse(const Duration(seconds: 1));
      expect(controller.startCalls, 0);
      expect(c.read(powerProvider), PowerState.stopped);
      // The user still wants the tunnel, so the next launch keeps the intent.
      expect(c.read(legacySettingsProvider).vpnRunning, isTrue);
    });
  });

  test('启动成功后 watchdog 不再触发', () {
    fakeAsync((async) {
      final controller = FakeVpnController(prepared: true);
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {'app_work_mode': 'normal'},
      });
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(controller),
          ruleRepositoryProvider.overrideWithValue(null),
        ],
      );
      addTearDown(c.dispose);

      c.read(powerProvider.notifier).toggle();
      async.flushMicrotasks();
      expect(c.read(powerProvider), PowerState.running);

      // `status()` keeps saying running, so an expired watchdog must not corrupt state.
      controller.statusValue = const VpnStatus(running: true, persisted: true);
      async.elapse(const Duration(seconds: 120));
      expect(c.read(powerProvider), PowerState.running);
    });
  });
}

void _expressMode() {
  group('极速模式 prefs 视图', () {
    test('DNS 键读 diting_express_prefs，UI 键仍读全局容器', () {
      final store = MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'selected_provider_id': 'preset_google_dns',
          'theme_color_style': 'moss',
          // App-level rules do not enter the dataset container in 1.4.3.
          'excluded_app_packages': ['com.example.skip'],
        },
        'diting_express_prefs': {
          'selected_provider_id': 'preset_dnspod_dns',
          'ipv6_mode': 'disabled',
        },
        'express_vpn_prefs': {'express_vpn_running': true},
      });
      final normal = LegacySettings(store);
      final express = normal.forExpress();

      expect(express.selectedProviderId, 'preset_dnspod_dns');
      expect(express.ipv6ModeRaw, 'disabled');
      expect(express.excludedPackages, {'com.example.skip'});
      expect(express.expressVpnRunning, isTrue);
      expect(express.paletteRaw, 'moss');

      expect(normal.selectedProviderId, 'preset_google_dns');
      expect(normal.expressVpnRunning, isTrue);
    });

    test('缺失键回落到旧版默认值', () {
      final express = expressSettings({}).forExpress();
      expect(express.selectedProviderId, 'preset_alidns_dns');
      expect(express.resolutionModeRaw, 'single');
      expect(express.cacheEnabled, isTrue);
      expect(express.bootstrapEnabled, isTrue);
      expect(express.ipv6ModeRaw, 'auto');
      expect(express.expressVpnRunning, isFalse);
    });
  });

  group('极速模式电源状态机', () {
    ProviderContainer container({
      required FakeVpnController normal,
      required FakeVpnController express,
      Map<String, Object?> dnsPrefs = const {},
      Map<String, Object?> expressRunning = const {},
    }) {
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {'app_work_mode': 'express'},
        // The UI and the engine both read the express data set, so its container holds the keys.
        'diting_express_prefs': {
          'selected_provider_id': 'preset_dnspod_dns',
          'ipv6_mode': 'disabled',
          ...dnsPrefs,
        },
        'express_vpn_prefs': expressRunning,
      });
      final c = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(normal),
          expressVpnControllerProvider.overrideWithValue(express),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('启动走极速通道、采用极速数据集的 DNS 配置并写 express_vpn_running', () async {
      final normal = FakeVpnController();
      final express = FakeVpnController();
      final c = container(normal: normal, express: express);
      expect(c.read(powerProvider), PowerState.stopped);

      await c.read(powerProvider.notifier).toggle();
      expect(c.read(powerProvider), PowerState.running);
      expect(express.startCalls, 1);
      expect(normal.startCalls, 0);

      final request = express.lastRequest!;
      expect(request.bypassLan, isFalse);
      expect(request.ipv6Mode, 'disabled');
      final json = jsonDecode(request.dnsConfig) as Map;
      final providers = json['providers'] as List;
      expect((providers.first as Map)['id'], 'preset_dnspod_dns');

      final settings = c.read(legacySettingsProvider);
      expect(settings.expressVpnRunning, isTrue);
      expect(settings.vpnRunning, isFalse);
    });

    // Regression: the app used to write DNS settings to the normal container while the express
    // engine read `diting_express_prefs`, so the notification ignored the user's selection.
    test('极速模式里选择的解析模式进入数据集的设置与通知文案', () async {
      final c = container(
        normal: FakeVpnController(),
        express: FakeVpnController(),
      );
      c.read(resolutionModeProvider.notifier).select(ResolutionMode.smart);
      // The settings write is what the dataset switch follows; the engine reads prefs at start.
      expect(
        c.read(legacySettingsProvider).dnsContainer,
        LegacySettings.expressContainer,
      );
      expect(
        c
            .read(legacyPrefsStoreProvider)
            .read(LegacySettings.expressContainer, 'dns_resolution_mode'),
        'smart_prediction',
      );

      await c.read(powerProvider.notifier).toggle();
      expect(c.read(powerProvider), PowerState.running);
      expect(
        c
            .read(legacyPrefsStoreProvider)
            .read(LegacySettings.notificationContainer, 'default_express_text'),
        '运行中 · [智能选择] 2 个服务商',
      );
    });

    test('残留运行标志经原生状态回写为停止', () async {
      final express = FakeVpnController();
      final c = container(
        normal: FakeVpnController(),
        express: express,
        expressRunning: {'express_vpn_running': true},
      );
      expect(c.read(powerProvider), PowerState.starting);
      await c.read(powerProvider.notifier).syncStatus();
      expect(c.read(powerProvider), PowerState.stopped);
      expect(c.read(legacySettingsProvider).expressVpnRunning, isFalse);
    });

    test('切回普通模式会停止极速隧道', () async {
      final express = FakeVpnController();
      final c = container(normal: FakeVpnController(), express: express);
      await c.read(powerProvider.notifier).toggle();
      expect(c.read(powerProvider), PowerState.running);

      c.read(workModeProvider.notifier).select(AppWorkMode.normal);
      await Future<void>.delayed(Duration.zero);
      expect(express.stopCalls, 1);
      expect(c.read(powerProvider), PowerState.stopped);
    });

    test('原生启动失败进入 error 且不留下运行标志', () async {
      final express = FakeVpnController(started: false, error: 'no tun');
      final c = container(normal: FakeVpnController(), express: express);
      await c.read(powerProvider.notifier).toggle();
      expect(c.read(powerProvider), PowerState.error);
      expect(c.read(powerProvider.notifier).lastError, 'no tun');
      expect(c.read(legacySettingsProvider).expressVpnRunning, isFalse);
    });
  });
}

LegacySettings expressSettings(Map<String, Object?> values) => LegacySettings(
  MemoryLegacyPrefsStore({
    'diting_settings': {'app_work_mode': 'express'},
    'diting_express_prefs': values,
  }),
);
