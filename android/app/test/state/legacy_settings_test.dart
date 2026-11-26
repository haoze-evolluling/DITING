import 'package:diting_android/app/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:diting_android/app/theme/colors.dart';
import 'package:diting_android/app/theme/layout.dart';
import 'package:diting_android/data/native/background_bridge.dart';
import 'package:diting_android/data/prefs/ipv6_mode.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/appearance_providers.dart';
import 'package:diting_android/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegacySettings 读写', _legacySettings);
  group('设置键与设置态 provider', _settingsCatalog);
}

void _legacySettings() {
  MemoryLegacyPrefsStore legacyStore() => MemoryLegacyPrefsStore({
    'dns_vpn_prefs': {
      'app_theme_mode': 'dark',
      'theme_color_style': 'indigo',
      'home_component_opacity': 0.8,
      'home_poem_opacity': 0.4,
      'home_sentence_running': '运行句子',
      'home_sentence_stopped': '停止句子',
      'bottom_bar_destinations':
          '["home","network_tools","settings","network_tools","bogus"]',
      'bottom_bar_haptic_enabled': false,
      'dns_resolution_mode': 'parallel_race',
    },
    'diting_settings': {
      'app_work_mode': 'normal',
      'work_mode_initial_selected': true,
    },
  });

  group('LegacySettings 读取', () {
    test('外观键按旧版键名与值域解析', () {
      final settings = LegacySettings(legacyStore());

      expect(settings.themeModeRaw, 'dark');
      expect(settings.paletteRaw, 'indigo');
      expect(settings.componentOpacity, 0.8);
      expect(settings.homeOpacity('home_power_button_opacity'), 0.8);
      expect(settings.homeOpacity('home_poem_opacity'), 0.4);
      expect(settings.homeSentences.running, '运行句子');
      expect(settings.homeSentences.stopped, '停止句子');
      expect(settings.hapticEnabled, isFalse);
    });

    test('工作模式 / 解析模式读取旧容器', () {
      final settings = LegacySettings(legacyStore());
      expect(settings.workModeRaw, 'normal');
      expect(settings.workModeSelected, isTrue);
      expect(settings.resolutionModeRaw, 'parallel_race');
    });

    test('读取当前三态键，缺省为仅 IPv4', () {
      final empty = LegacySettings(MemoryLegacyPrefsStore());
      expect(empty.ipv6Mode, Ipv6Mode.ipv4);

      final settings = LegacySettings(
        MemoryLegacyPrefsStore({
          'dns_vpn_prefs': {'vpn_ipv6_mode': 'ipv6'},
        }),
      );
      expect(settings.ipv6Mode, Ipv6Mode.ipv6);
    });

    test('写入三态只落当前键', () {
      final store = MemoryLegacyPrefsStore();
      final settings = LegacySettings(store);
      settings.setIpv6Mode(Ipv6Mode.ipv6);
      expect(settings.ipv6Mode, Ipv6Mode.ipv6);
      expect(store.read('dns_vpn_prefs', 'vpn_ipv6_mode'), 'ipv6');
      expect(store.read('dns_vpn_prefs', 'vpn_ipv6_enabled'), isNull);
      expect(store.read('dns_vpn_prefs', 'dns_aaaa_enabled'), isNull);
    });

    test('路由列表读写去重并排序', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      settings.setVpnRouteAddress([' 10.0.0.0/8 ', '10.0.0.0/8', '::/0']);
      settings.setVpnRouteExcludeAddress(['192.168.0.0/16']);
      expect(settings.vpnRouteAddress, ['10.0.0.0/8', '::/0']);
      expect(settings.vpnRouteExcludeAddress, ['192.168.0.0/16']);
    });

    test('空存储返回 1.4.3 的默认值', () {
      final settings = LegacySettings(MemoryLegacyPrefsStore());
      expect(settings.themeModeRaw, isNull);
      expect(settings.paletteRaw, isNull);
      expect(settings.componentOpacity, 1);
      expect(
        settings.homeSentences.running,
        LegacySettings.defaultRunningSentence(
          lookupAppL10n(const Locale('zh')),
        ),
      );
      expect(
        settings.homeSentences.stopped,
        LegacySettings.defaultStoppedSentence(
          lookupAppL10n(const Locale('zh')),
        ),
      );
      expect(settings.bottomBarIds, LegacySettings.defaultBottomBarIds);
      expect(settings.hapticEnabled, isTrue);
      expect(settings.workModeRaw, 'normal');
      expect(settings.workModeSelected, isFalse);
      expect(settings.resolutionModeRaw, 'single');
    });

    test('显式值越界时按旧版钳位', () {
      final settings = LegacySettings(
        MemoryLegacyPrefsStore({
          'dns_vpn_prefs': {'home_poem_opacity': 0.01},
        }),
      );
      expect(settings.homeOpacity('home_poem_opacity'), 0.1);
    });
  });

  group('LegacySettings 写入', () {
    test('写回同名容器与键名', () {
      final store = MemoryLegacyPrefsStore();
      final settings = LegacySettings(store);

      settings.setThemeModeRaw('light');
      settings.setPaletteRaw('indigo');
      settings.setHomeOpacity('home_poem_opacity', 0.3);
      settings.setHomeSentences(running: 'a', stopped: 'b');
      settings.setBottomBarIds([
        'home',
        'feature_hub',
        'feature_hub',
        'settings',
        'network_tools',
        'app_traffic_stats',
      ]);
      settings.setHapticEnabled(false);
      settings.setWorkModeRaw('express');
      settings.setWorkModeSelected(true);
      settings.setResolutionModeRaw('smart_prediction');

      expect(store.read('dns_vpn_prefs', 'app_theme_mode'), 'light');
      expect(store.read('dns_vpn_prefs', 'theme_color_style'), 'indigo');
      expect(store.read('dns_vpn_prefs', 'home_poem_opacity'), 0.3);
      expect(store.read('dns_vpn_prefs', 'home_sentence_running'), 'a');
      expect(
        store.read('dns_vpn_prefs', 'bottom_bar_destinations'),
        '["home","feature_hub","settings","network_tools"]',
      );
      expect(store.read('dns_vpn_prefs', 'bottom_bar_haptic_enabled'), false);
      expect(store.read('diting_settings', 'app_work_mode'), 'express');
      expect(store.read('diting_settings', 'work_mode_initial_selected'), true);
      expect(
        store.read('dns_vpn_prefs', 'dns_resolution_mode'),
        'smart_prediction',
      );
    });

    test('清空工作模式会移除两个键而不是写 false', () {
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {
          'app_work_mode': 'express',
          'work_mode_initial_selected': true,
        },
      });
      LegacySettings(store).clearWorkModeSelection();
      expect(store.read('diting_settings', 'app_work_mode'), isNull);
      expect(
        store.read('diting_settings', 'work_mode_initial_selected'),
        isNull,
      );
    });
  });

  group('枚举落盘值', () {
    test('GOLD 色板仍存历史值 indigo', () {
      expect(AppPalette.gold.storageValue, 'indigo');
      expect(AppPalette.fromStorageValue('indigo'), AppPalette.gold);
      expect(AppPalette.fromStorageValue('nope'), AppPalette.system);
    });

    test('未知的旧工作模式安全回退普通模式', () {
      expect(AppWorkMode.fromStorageValue('dns'), AppWorkMode.normal);
      expect(AppWorkMode.fromStorageValue(null), AppWorkMode.normal);
    });

    test('解析模式落盘值与枚举名不同名', () {
      expect(ResolutionMode.smart.storageValue, 'smart_prediction');
      expect(ResolutionMode.parallel.storageValue, 'parallel_race');
      expect(
        ResolutionMode.fromStorageValue('parallel_race'),
        ResolutionMode.parallel,
      );
    });

    test('底栏 id 与旧版一致', () {
      expect(BottomBarDestination.appTraffic.storageValue, 'app_traffic_stats');
      expect(BottomBarDestination.networkTools.storageValue, 'network_tools');
      expect({
        for (final destination in BottomBarDestination.values)
          destination.storageValue,
      }, LegacySettings.bottomBarIdValues);
    });
  });

  group('Provider 接入旧值', () {
    ProviderContainer containerWith(LegacyPrefsStore store) {
      final container = ProviderContainer(
        overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('启动即读到旧设置', () {
      final store = legacyStore();
      final container = containerWith(store);

      expect(container.read(themeModeProvider), AppThemeMode.dark);
      expect(container.read(paletteProvider), AppPalette.gold);
      expect(container.read(hapticProvider), isFalse);
      expect(container.read(homeOpacityProvider)[HomeLayer.poem], 0.4);
      expect(container.read(homeSentenceProvider).running, '运行句子');
      expect(container.read(bottomBarProvider), [
        BottomBarDestination.home,
        BottomBarDestination.networkTools,
        BottomBarDestination.settings,
      ]);
      expect(container.read(workModeProvider), AppWorkMode.normal);
      expect(container.read(resolutionModeProvider), ResolutionMode.parallel);
      expect(container.read(workModeSelectedProvider), isTrue);
    });

    test('用户修改后立刻写回旧键', () {
      final store = MemoryLegacyPrefsStore();
      final container = containerWith(store);

      container.read(themeModeProvider.notifier).select(AppThemeMode.light);
      container.read(paletteProvider.notifier).select(AppPalette.gold);
      container.read(hapticProvider.notifier).toggle(false);
      container
          .read(homeOpacityProvider.notifier)
          .set(HomeLayer.powerButton, 0.6);
      container
          .read(homeSentenceProvider.notifier)
          .set(running: '新句子', stopped: '旧停止');
      container.read(workModeProvider.notifier).select(AppWorkMode.express);
      container
          .read(resolutionModeProvider.notifier)
          .select(ResolutionMode.primaryBackup);

      expect(store.read('dns_vpn_prefs', 'app_theme_mode'), 'light');
      expect(store.read('dns_vpn_prefs', 'theme_color_style'), 'indigo');
      expect(store.read('dns_vpn_prefs', 'bottom_bar_haptic_enabled'), false);
      expect(store.read('dns_vpn_prefs', 'home_power_button_opacity'), 0.6);
      expect(store.read('dns_vpn_prefs', 'home_sentence_running'), '新句子');
      expect(store.read('diting_settings', 'app_work_mode'), 'express');
      expect(
        store.read('diting_express_prefs', 'dns_resolution_mode'),
        'primary_backup',
      );
      expect(store.read('dns_vpn_prefs', 'dns_resolution_mode'), isNull);
    });

    test('底栏改动按旧版 JSON 数组格式保存', () {
      final store = MemoryLegacyPrefsStore();
      final container = containerWith(store);

      final toggled = container
          .read(bottomBarProvider.notifier)
          .toggle(BottomBarDestination.settings);

      expect(toggled, isTrue);
      expect(
        store.read('dns_vpn_prefs', 'bottom_bar_destinations'),
        '["home","feature_hub","log_dashboard","settings"]',
      );
    });
  });
}

void _settingsCatalog() {
  group('旧版设置键（第三轮新增）', () {
    late LegacyPrefsStore store;
    late LegacySettings settings;

    setUp(() {
      store = MemoryLegacyPrefsStore();
      settings = LegacySettings(store);
    });

    test('日志模式默认 all，且写在数据集容器里', () {
      expect(settings.dnsLogModeRaw, 'all');
      settings.setDnsLogModeRaw('blocked_and_errors');
      expect(store.read('dns_vpn_prefs', 'dns_log_mode'), 'blocked_and_errors');
      final express = LegacySettings(
        store,
        dnsContainer: LegacySettings.expressContainer,
      );
      expect(express.dnsLogModeRaw, 'all', reason: '简洁模式是另一份数据');
      express.setDnsLogModeRaw('off');
      expect(store.read('diting_express_prefs', 'dns_log_mode'), 'off');
    });

    test('日志保留天数默认 7 且被夹在 1–30', () {
      expect(settings.logRetentionDays, 7);
      settings.setLogRetentionDays(0);
      expect(settings.logRetentionDays, 1);
      settings.setLogRetentionDays(99);
      expect(settings.logRetentionDays, 30);
    });

    test('通知栏四键写在独立容器 notification_settings_prefs', () {
      expect(settings.notificationPersistent, isTrue);
      expect(settings.notificationSpeed, isFalse);
      settings.setNotificationPersistent(false);
      settings.setNotificationSpeed(true);
      settings.setNotificationTexts(running: '守护中', stopped: '已停止');
      expect(store.read('notification_settings_prefs', 'persistent'), isFalse);
      expect(store.read('notification_settings_prefs', 'speed'), isTrue);
      expect(
        store.read('notification_settings_prefs', 'custom_running_text'),
        '守护中',
      );
      expect(store.read('dns_vpn_prefs', 'persistent'), isNull);
    });

    test('通知详情项：没有新键时沿用旧的网速开关，写入时同步旧键', () {
      expect(settings.notificationStatsItems, isEmpty);
      settings.setNotificationSpeed(true);
      expect(settings.notificationStatsItems, ['speed']);

      settings.setNotificationStatsItems(['filtered', 'total', 'filtered']);
      expect(
        store.read('notification_settings_prefs', 'stats_items'),
        'filtered,total',
      );
      expect(store.read('notification_settings_prefs', 'speed'), isFalse);

      settings.setNotificationSpeed(true);
      expect(settings.notificationStatsItems, ['filtered', 'total', 'speed']);
      settings.setNotificationSpeed(false);
      expect(settings.notificationStatsItems, ['filtered', 'total']);
    });

    test('软件背景：启用、当前、历史清单三个键', () {
      expect(settings.customBackgroundEnabled, isFalse);
      expect(settings.customBackgroundUri, isNull);
      expect(settings.customBackgroundUris, isEmpty);

      settings.setCustomBackgroundEnabled(true);
      settings.setCustomBackgroundUri('content://picked/1');
      settings.setCustomBackgroundUris(['content://picked/1', 'content://2']);
      expect(settings.customBackgroundEnabled, isTrue);
      expect(settings.customBackgroundUri, 'content://picked/1');
      expect(settings.customBackgroundUris, [
        'content://picked/1',
        'content://2',
      ]);
    });

    test('历史清单遇到坏 JSON 时返回空表而不是抛异常', () {
      store.putString('dns_vpn_prefs', 'custom_background_uris', '{not json');
      expect(settings.customBackgroundUris, isEmpty);
    });
  });

  group('设置态 provider（内存 store）', () {
    _FakeBackgroundBridge? bridge;

    ProviderContainer container() {
      final fake = _FakeBackgroundBridge();
      bridge = fake;
      final c = ProviderContainer(
        overrides: [backgroundBridgeProvider.overrideWithValue(fake)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('日志模式三档枚举与落盘值', () {
      expect(LegacyLogMode.values.length, 3);
      expect(
        [for (final mode in LegacyLogMode.values) mode.storageValue],
        ['all', 'blocked_and_errors', 'off'],
      );
      final c = container();
      c.read(logModeProvider.notifier).select(LegacyLogMode.off);
      expect(c.read(logModeProvider), LegacyLogMode.off);
    });

    test('IPv6 三态默认仅 IPv4 且可切换', () {
      final c = container();
      final notifier = c.read(foregroundBackgroundProvider.notifier);
      expect(c.read(foregroundBackgroundProvider).ipv6Mode, Ipv6Mode.ipv4);

      notifier.setIpv6Mode(Ipv6Mode.ipv4);
      expect(c.read(foregroundBackgroundProvider).ipv6Mode, Ipv6Mode.ipv4);

      notifier.setIpv6Mode(Ipv6Mode.ipv6);
      expect(c.read(foregroundBackgroundProvider).ipv6Mode, Ipv6Mode.ipv6);
    });

    test('开机自启动开关默认关闭且可独立切换', () {
      final c = container();
      expect(c.read(autoStartOnBootProvider), isFalse);

      c.read(autoStartOnBootProvider.notifier).toggle(true);
      expect(c.read(autoStartOnBootProvider), isTrue);
      expect(c.read(autoStartOnLaunchProvider), isFalse);
    });

    test('路由列表去空去重并排序', () {
      final c = container();
      c.read(foregroundBackgroundProvider.notifier).setRouteAddress([
        ' 10.0.0.0/8 ',
        '10.0.0.0/8',
        '::/0',
        ' ',
      ]);
      expect(c.read(foregroundBackgroundProvider).routeAddress, [
        '10.0.0.0/8',
        '::/0',
      ]);
    });

    test('背景图：添加会同时更新当前与清单，移除当前会退到清单末尾', () {
      final c = container();
      final notifier = c.read(customBackgroundProvider.notifier);
      notifier.add('content://1');
      notifier.add('content://2');
      var state = c.read(customBackgroundProvider);
      expect(state.uris, ['content://1', 'content://2']);
      expect(state.currentUri, 'content://2');
      expect(state.enabled, isTrue, reason: '添加一张后应自动启用');

      notifier.remove('content://2');
      state = c.read(customBackgroundProvider);
      expect(state.uris, ['content://1']);
      expect(state.currentUri, 'content://1');
      expect(bridge!.released, ['content://2']);
    });
  });

  group('底栏上限回到旧版的 4', () {
    test('maxDockDestinations 与 LegacySettings.bottomBarMaxCount 一致', () {
      expect(maxDockDestinations, LegacySettings.bottomBarMaxCount);
      expect(maxDockDestinations, 4);
    });
  });
}

class _FakeBackgroundBridge extends BackgroundBridge {
  final List<String> released = [];

  @override
  Future<bool> release(String uri) async {
    released.add(uri);
    return true;
  }
}
