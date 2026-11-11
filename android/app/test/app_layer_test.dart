// Theme assembly, the appearance providers and the enum labels that reach the screen.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/app/theme/layout.dart';
import 'package:diting_shared/app/theme/manager.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_vpn_controller.dart';

void main() {
  group('主题与外观', _appLayer);
  // Every supported language must produce display text, not a source identifier.
  for (final locale in AppL10n.supportedLocales) {
    group(
      '枚举文案 ${locale.languageCode}',
      () => _enumDisplay(lookupAppL10n(locale)),
    );
  }
}

void _appLayer() {
  group('buildAppTheme 装配顺序', () {
    // Order matters: pure black goes after seededColorScheme, before surface recomputes a tint
    test('纯黑主题的 surface 是纯黑', () {
      final theme = buildAppTheme(
        const AppThemeSpec(
          seedColor: Color(0xFF007AFF),
          brightness: Brightness.dark,
          pureBlack: true,
        ),
      );
      expect(theme.colorScheme.surface, const Color(0xFF000000));
      expect(theme.brightness, Brightness.dark);
    });

    test('深色主题带 ElevatedColorScheme 扩展，浅色不带', () {
      final dark = buildAppTheme(
        const AppThemeSpec(
          seedColor: Color(0xFF007AFF),
          brightness: Brightness.dark,
        ),
      );
      final light = buildAppTheme(
        const AppThemeSpec(
          seedColor: Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
      );
      expect(dark.extension<ElevatedColorScheme>(), isNotNull);
      expect(light.extension<ElevatedColorScheme>(), isNull);
    });

    test('形状与排版被装配进去', () {
      final theme = buildAppTheme(
        const AppThemeSpec(
          seedColor: Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
      );
      // Without withAppShapes the Card radius stays the M3 default.
      expect(theme.cardTheme.shape, isNotNull);
      expect(theme.textTheme.bodyMedium?.fontFamilyFallback, isNotNull);
    });
  });

  group('AppThemeCache', () {
    test('同一 spec 返回同一实例（否则 ThemeCrossFade 每帧闪）', () {
      final cache = AppThemeCache();
      const spec = AppThemeSpec(
        seedColor: Color(0xFF007AFF),
        brightness: Brightness.light,
      );
      expect(identical(cache.of(spec), cache.of(spec)), isTrue);
    });

    test('缓存容量有上界（避免主题切换久了无限增长）', () {
      final cache = AppThemeCache();
      for (var i = 0; i < AppPalette.values.length * 4; i++) {
        cache.of(
          AppThemeSpec(
            seedColor: Color(0xFF000000 | (i * 977) & 0xFFFFFF),
            brightness: i.isEven ? Brightness.light : Brightness.dark,
          ),
        );
      }
      expect(cache.length, lessThanOrEqualTo(AppThemeCache.maxEntries));
    });
  });

  group('AppPalette', () {
    test('system 用默认种子色；blue 就是默认蓝，两者 effectiveSeed 相同', () {
      expect(AppPalette.system.effectiveSeed, defaultPrimaryColor);
      expect(AppPalette.blue.effectiveSeed, defaultPrimaryColor);
      for (final palette in AppPalette.values) {
        if (palette == AppPalette.system || palette == AppPalette.blue) {
          continue;
        }
        expect(palette.seed, isNotNull, reason: '${palette.name} 缺种子色');
        expect(
          palette.effectiveSeed,
          isNot(defaultPrimaryColor),
          reason: '${palette.name} 不该复用默认蓝',
        );
      }
    });

    test('fromSeed 能还原色板，未知种子回退 system', () {
      expect(AppPalette.fromSeed(AppPalette.purple.seed!), AppPalette.purple);
      expect(AppPalette.fromSeed(const Color(0xFF123456)), AppPalette.system);
    });
  });

  group('外观 provider', () {
    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('切换色板后 effectiveSeed 跟着变', () {
      final c = container();
      // Unset `theme_color_style` falls back to SYSTEM in 1.4.3, which degrades to M3 blue without
      // Monet
      expect(c.read(paletteProvider), AppPalette.system);
      c.read(paletteProvider.notifier).select(AppPalette.purple);
      expect(
        c.read(paletteProvider).effectiveSeed,
        AppPalette.purple.effectiveSeed,
      );
    });

    test('底栏至少留 2 项、最多 $maxDockDestinations 项', () {
      final c = container();
      final notifier = c.read(bottomBarProvider.notifier);
      final defaults = c.read(bottomBarProvider);
      expect(defaults.length, greaterThanOrEqualTo(2));
      expect(defaults.length, lessThanOrEqualTo(maxDockDestinations));

      for (final destination in BottomBarDestination.values) {
        notifier.toggle(destination);
      }
      expect(c.read(bottomBarProvider).length, maxDockDestinations);

      for (final destination in BottomBarDestination.values) {
        notifier.toggle(destination);
      }
      expect(c.read(bottomBarProvider).length, greaterThanOrEqualTo(2));
    });

    test('底栏项可调整顺序，越界移动被忽略', () {
      final c = container();
      final notifier = c.read(bottomBarProvider.notifier);
      final defaults = List.of(c.read(bottomBarProvider));
      notifier.move(0, defaults.length - 1);
      expect(c.read(bottomBarProvider), [...defaults.skip(1), defaults.first]);
      notifier.move(0, defaults.length);
      expect(c.read(bottomBarProvider), [...defaults.skip(1), defaults.first]);
    });

    test('重置底栏回到默认配置', () {
      final c = container();
      final notifier = c.read(bottomBarProvider.notifier);
      final defaults = List.of(c.read(bottomBarProvider));
      notifier.toggle(BottomBarDestination.settings);
      notifier.reset();
      expect(c.read(bottomBarProvider), defaults);
    });

    test('透明度被夹在 0.1–1.0', () {
      final c = container();
      final notifier = c.read(homeOpacityProvider.notifier);
      notifier.set(HomeLayer.powerButton, 0);
      expect(c.read(homeOpacityProvider)[HomeLayer.powerButton], 0.1);
      notifier.set(HomeLayer.powerButton, 5);
      expect(c.read(homeOpacityProvider)[HomeLayer.powerButton], 1.0);
    });
  });

  group('工作模式 provider', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          vpnControllerProvider.overrideWithValue(FakeVpnController()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('电源状态经真实桥接的 toggle 流转', () async {
      final c = container();
      final power = c.read(powerProvider.notifier);
      expect(c.read(powerProvider), PowerState.stopped);

      power.toggle();
      expect(c.read(powerProvider), PowerState.starting);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(powerProvider), PowerState.running);

      power.toggle();
      expect(c.read(powerProvider), PowerState.stopping);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(powerProvider), PowerState.stopped);
    });

    test('busy 期间再点 toggle 被忽略', () async {
      final c = container();
      final power = c.read(powerProvider.notifier);
      power.toggle();
      power.toggle();
      expect(c.read(powerProvider), PowerState.starting);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(powerProvider), PowerState.running);
    });

    test('未授予 VPN 权限时保持启动中，授权后继续', () async {
      final fake = FakeVpnController(prepared: false);
      final c = ProviderContainer(
        overrides: [vpnControllerProvider.overrideWithValue(fake)],
      );
      addTearDown(c.dispose);
      await c.read(powerProvider.notifier).toggle();
      expect(c.read(powerProvider), PowerState.starting);
      expect(fake.startCalls, 0);

      fake.grantPermission();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(powerProvider), PowerState.running);
      expect(fake.startCalls, 1);
    });

    test('启动失败进入 error 状态', () async {
      final fake = FakeVpnController(started: false, error: 'boom');
      final c = ProviderContainer(
        overrides: [vpnControllerProvider.overrideWithValue(fake)],
      );
      addTearDown(c.dispose);
      await c.read(powerProvider.notifier).toggle();
      expect(c.read(powerProvider), PowerState.error);
      expect(c.read(powerProvider.notifier).lastError, 'boom');
    });

    test('切换内置协议会重映射内置服务商并热更新运行中的引擎', () async {
      final fake = FakeVpnController();
      final c = ProviderContainer(
        overrides: [vpnControllerProvider.overrideWithValue(fake)],
      );
      addTearDown(c.dispose);
      await c.read(powerProvider.notifier).toggle();
      expect(c.read(presetProtocolProvider), ProviderProtocol.dns);

      expect(
        c.read(presetProtocolProvider.notifier).select(ProviderProtocol.doh),
        isTrue,
      );
      expect(c.read(selectedProviderProvider), 'preset_alidns_doh');
      expect(c.read(legacySettingsProvider).parallelRaceProviderIds, [
        'preset_alidns_doh',
        'preset_dnspod_doh',
      ]);
      // Non-switchable presets keep their own protocol.
      expect(
        presetIdForProtocol('preset_google_dns', DnsProtocol.doh),
        'preset_google_dns',
      );

      expect(
        await c.read(powerProvider.notifier).applyDnsConfigIfRunning(),
        isNull,
      );
      expect(fake.applyDnsConfigCalls, 1);
      expect(fake.lastAppliedDnsConfig, contains('preset_alidns_doh'));
    });

    test('端口夹在 1024–65535', () {
      final c = container();
      final notifier = c.read(serverPortProvider.notifier);
      notifier.set(80);
      expect(c.read(serverPortProvider), 1024);
      notifier.set(70000);
      expect(c.read(serverPortProvider), 65535);
      notifier.set(8080);
      expect(c.read(serverPortProvider), 8080);
    });

    test('竞速至少 2 个服务商', () {
      final c = container();
      final notifier = c.read(raceProvidersProvider.notifier);
      final initial = c.read(raceProvidersProvider).length;
      expect(initial, greaterThanOrEqualTo(2));
      for (final id in c.read(raceProvidersProvider).toList()) {
        notifier.toggle(id);
      }
      expect(c.read(raceProvidersProvider).length, greaterThanOrEqualTo(2));
    });

    test('selectedProviderProvider 拒绝不存在的 id', () {
      final c = container();
      final before = c.read(selectedProviderProvider);
      c.read(selectedProviderProvider.notifier).select('does-not-exist');
      expect(c.read(selectedProviderProvider), before);
    });
  });
}

/// Guards enums reach the screen through `.label`; a bare enum renders `ProviderProtocol.doh`
void _enumDisplay(AppL10n l10n) {
  /// A source identifier like "EnumType.value" must never appear in user text.
  void expectNoRawEnumLiteral(String text, String what) {
    expect(
      RegExp(r'\b[A-Z][A-Za-z]*\.[a-z][A-Za-z]*\b').hasMatch(text),
      isFalse,
      reason: '$what 里出现了枚举源码标识符：$text',
    );
  }

  // 1.4.3's preset providers live under `preset_*` ids; the UI must use that catalog.
  final catalog = defaultProviderCatalog();

  group('providerEndpointOf', () {
    test('拼的是协议 label 而不是枚举名', () {
      for (final provider in catalog) {
        final text = providerEndpointOf(provider.id);
        expectNoRawEnumLiteral(text, '端点文案(${provider.id})');
        expect(
          text,
          startsWith(provider.protocol.label),
          reason: '应以协议 label 开头：$text',
        );
        expect(text, contains(provider.address));
      }
    });
  });

  group('枚举展示字段', () {
    test('每个枚举的 label/title/summary 都不含源码标识符', () {
      for (final protocol in ProviderProtocol.values) {
        expectNoRawEnumLiteral(
          protocol.label,
          'ProviderProtocol.${protocol.name}',
        );
      }
      for (final kind in RuleKind.values) {
        expectNoRawEnumLiteral(kind.title(l10n), 'RuleKind.${kind.name}.title');
        expectNoRawEnumLiteral(
          kind.summary(l10n),
          'RuleKind.${kind.name}.summary',
        );
      }
      for (final mode in AppWorkMode.values) {
        expectNoRawEnumLiteral(
          mode.title(l10n),
          'AppWorkMode.${mode.name}.title',
        );
        expectNoRawEnumLiteral(
          mode.badge(l10n),
          'AppWorkMode.${mode.name}.badge',
        );
        expectNoRawEnumLiteral(
          mode.summary(l10n),
          'AppWorkMode.${mode.name}.summary',
        );
      }
      for (final state in PowerState.values) {
        expectNoRawEnumLiteral(
          state.label(l10n),
          'PowerState.${state.name}.label',
        );
      }
      for (final resolution in ResolutionMode.values) {
        expectNoRawEnumLiteral(
          resolution.label(l10n),
          'ResolutionMode.${resolution.name}',
        );
      }
      for (final layer in HomeLayer.values) {
        expectNoRawEnumLiteral(layer.label(l10n), 'HomeLayer.${layer.name}');
      }
      for (final destination in BottomBarDestination.values) {
        expectNoRawEnumLiteral(
          destination.label(l10n),
          'BottomBarDestination.${destination.name}',
        );
      }
      for (final palette in AppPalette.values) {
        expectNoRawEnumLiteral(
          palette.label(l10n),
          'AppPalette.${palette.name}',
        );
      }
      for (final themeMode in AppThemeMode.values) {
        expectNoRawEnumLiteral(
          themeMode.label(l10n),
          'AppThemeMode.${themeMode.name}',
        );
      }
      for (final source in RuleSource.values) {
        expectNoRawEnumLiteral(
          source.label(l10n),
          'RuleSource.${source.name}',
        );
      }
      for (final serverStatus in ServerStatus.values) {
        expectNoRawEnumLiteral(
          serverStatus.label(l10n),
          'ServerStatus.${serverStatus.name}',
        );
      }
    });
  });
}
