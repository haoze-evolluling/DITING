import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/app/theme/colors.dart';
import 'package:diting_android/app/theme/layout.dart';
import 'package:diting_android/app/theme/manager.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/state/appearance_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_vpn_controller.dart';

void main() {
  group('主题与外观', _appLayer);
  for (final locale in AppL10n.supportedLocales) {
    group(
      '枚举文案 ${locale.languageCode}',
      () => _enumDisplay(lookupAppL10n(locale)),
    );
  }
}

void _appLayer() {
  group('buildAppTheme 装配顺序', () {
    test('纯黑、深色扩展与形状排版按规格装配', () {
      final pureDark = buildAppTheme(
        const AppThemeSpec(
          seedColor: Color(0xFF007AFF),
          brightness: Brightness.dark,
          pureBlack: true,
        ),
      );
      expect(pureDark.colorScheme.surface, const Color(0xFF000000));
      expect(pureDark.brightness, Brightness.dark);
      expect(pureDark.extension<ElevatedColorScheme>(), isNotNull);

      final light = buildAppTheme(
        const AppThemeSpec(
          seedColor: Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
      );
      expect(light.extension<ElevatedColorScheme>(), isNull);
      expect(light.cardTheme.shape, isNotNull);
      expect(light.timePickerTheme.shape, isNotNull);
      expect(light.datePickerTheme.shape, isNotNull);
      expect(light.datePickerTheme.rangePickerShape, isNotNull);
      expect(light.textTheme.bodyMedium?.fontFamilyFallback, isNotNull);
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

  });
}

void _enumDisplay(AppL10n l10n) {
  void expectNoRawEnumLiteral(String text, String what) {
    expect(
      RegExp(r'\b[A-Z][A-Za-z]*\.[a-z][A-Za-z]*\b').hasMatch(text),
      isFalse,
      reason: '$what 里出现了枚举源码标识符：$text',
    );
  }

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
    });
  });
}
