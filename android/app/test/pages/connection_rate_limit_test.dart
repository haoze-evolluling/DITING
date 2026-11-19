import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/pages/network/connection_rate_limit_page.dart';
import 'package:diting_android/pages/network/lan_rate_limit_page.dart';
import 'package:diting_android/routes/connection_rate_limit_routes.dart';
import 'package:diting_android/routes/lan_rate_limit_routes.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/widgets/rate_limit_stepper_row.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_vpn_controller.dart';
import '../support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  group('连接限速文档', () {
    test('参数写入隧道文档，并在极速模式保持关闭', () {
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {'app_work_mode': 'normal'},
      });
      final settings = LegacySettings(store);
      settings.setConnectionRateLimitEnabled(true);
      settings.setConnectionRateLimitRate(80);
      settings.setConnectionRateLimitBurst(160);

      final normal = buildDnsConfig(settings).toJson(settings);
      expect(normal['connectionRateLimit'], {
        'enabled': true,
        'rate': 80,
        'burst': 160,
      });
      expect(normal.containsKey('rateLimit'), isFalse);

      store.putString('diting_settings', 'app_work_mode', 'express');
      final express = buildDnsConfig(settings).toJson(settings);
      expect(express['connectionRateLimit'], {
        'enabled': false,
        'rate': 80,
        'burst': 160,
      });
    });

    test('运行中的普通隧道热应用共享参数', () async {
      final store = MemoryLegacyPrefsStore({
        'diting_settings': {'app_work_mode': 'normal'},
      });
      final fake = FakeVpnController();
      final container = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await container.read(powerProvider.notifier).toggle();
      final settings = container.read(legacySettingsProvider);
      settings.setConnectionRateLimitEnabled(true);
      settings.setConnectionRateLimitRate(80);
      settings.setConnectionRateLimitBurst(160);

      expect(
        await container.read(powerProvider.notifier).applyDnsConfigIfRunning(),
        isNull,
      );
      expect(fake.applyDnsConfigCalls, 1);
      expect(
        fake.lastAppliedDnsConfig,
        contains(
          '"connectionRateLimit":{"enabled":true,"rate":80,"burst":160}',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
  });

  testWidgets('连接限速页在 320dp 英文与 1.3 倍字号下可操作且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final store = MemoryLegacyPrefsStore({
      'diting_settings': {'app_work_mode': 'normal'},
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(FakeVpnController()),
        ],
        child: DitingApp(initialLocation: ConnectionRateLimitPaths.root),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Connection rate limiting'), findsWidgets);
    final scrollable = find
        .descendant(
          of: find.byType(ConnectionRateLimitPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byType(CommonSwitch),
      160,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, 120));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CommonSwitch));
    await tester.pump();
    expect(store.read('dns_vpn_prefs', 'connection_rate_limit_enabled'), true);

    final rateRow = find.widgetWithText(
      RateLimitStepperRow,
      'Requests per second',
    );
    await tester.scrollUntilVisible(rateRow, 160, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, 100));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: rateRow, matching: find.byType(IconButton)).at(1),
    );
    await tester.pump();
    expect(store.read('dns_vpn_prefs', 'connection_rate_limit_rate'), 55);
    expect(tester.takeException(), isNull);
  });

  testWidgets('局域网限速页四个分区可操作且名单用浮层编辑', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final store = MemoryLegacyPrefsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          appLocaleProvider.overrideWithValue(const Locale('en')),
          legacyPrefsStoreProvider.overrideWithValue(store),
          vpnControllerProvider.overrideWithValue(FakeVpnController()),
        ],
        child: DitingApp(initialLocation: LanRateLimitPaths.root),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Rate limit switch'), findsOneWidget);
    final scrollable = find
        .descendant(
          of: find.byType(LanRateLimitPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Rate and burst'),
      160,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Rate and burst'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Client aggregation'),
      160,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Client aggregation'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(ListItem, 'Manage list'),
      160,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Exempt list'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListItem, 'Manage list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '10.0.0.1, 10.0.0.0/8');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(
      store.read('dns_vpn_prefs', 'lan_rate_limit_exempt'),
      '10.0.0.1, 10.0.0.0/8',
    );
    expect(tester.takeException(), isNull);
  });
}
