// Desktop hub blocking mode (docs/development/flutter-desktop-ui.md step 4): the master switch, the
// three answer modes, their addresses and interval, the temporary pause and the advanced switches.
// Every value must come from `/filter/config`, `/filter/stats` and `/filter/pause`; each write
// re-reads them, and a rejected write is reported instead of assumed.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_filter_config_models.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_config_page.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_advanced_card.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_lists_card.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_mode_card.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_pause_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpConfig(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) async {
    final fake = backend ?? FakeDesktopBackend();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: const DesktopApp(initialLocation: DesktopFilterConfigPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopFilterConfigPage)).l10n;

  Finder inSummary(Finder matching) => find.descendant(
    of: find.byType(FilterSummaryCard),
    matching: matching,
  );
  Finder inMode(Finder matching) =>
      find.descendant(of: find.byType(FilterModeCard), matching: matching);
  Finder inAdvanced(Finder matching) => find.descendant(
    of: find.byType(FilterAdvancedCard),
    matching: matching,
  );
  Finder inPause(Finder matching) =>
      find.descendant(of: find.byType(FilterPauseCard), matching: matching);

  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(
      tester.element(finder),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> clearMessages(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  test('缺字段按零值解析，模式与周期回落到默认值', () {
    final config = DesktopFilterConfig.fromJson(const {});
    expect(config.enabled, isFalse);
    expect(config.effectiveBlockMode, 'null_ip');
    expect(config.effectiveIntervalHours, 24);
    expect(config.bogusNxDomainNetworks, isEmpty);

    final parsed = DesktopFilterConfig.fromJson(const {
      'enabled': true,
      'blockMode': 'refused',
      'updateIntervalHours': 6,
      'bogusNxDomainNetworks': ['127.0.0.0/8'],
    });
    expect(parsed.toJson()['blockMode'], 'refused');
    expect(parsed.copyWith(enabled: false).enabled, isFalse);
    expect(parsed.copyWith(enabled: false).blockMode, 'refused');

    final pause = DesktopFilterPause.fromJson(const {
      'paused': true,
      'remainingSeconds': 90,
    });
    expect(pause.paused, isTrue);
    expect(pause.remaining, const Duration(seconds: 90));
    expect(pause.blockingEnabled, isTrue);
    expect(DesktopFilterPause.fromJson(const {}).blockingEnabled, isTrue);
  });

  testWidgets('页面显示服务返回的开关、指标与三种应答模式', (tester) async {
    await pumpConfig(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopFilterSummaryTitle), findsOneWidget);
    expect(
      tester.widget<DashboardSwitch>(inSummary(find.byType(DashboardSwitch))).value,
      isTrue,
    );
    expect(find.text(l10n.desktopFilterModeNullIp), findsOneWidget);
    expect(find.text(l10n.desktopFilterModeNxdomain), findsOneWidget);
    expect(find.text(l10n.desktopFilterModeRefused), findsOneWidget);
    expect(find.text(l10n.desktopFilterModeNullIpBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('总开关提交 enabled 并回显服务端状态', (tester) async {
    final backend = await pumpConfig(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inSummary(find.byType(DashboardSwitch)));

    final update = backend.filterConfigUpdates.single;
    expect(update['enabled'], isFalse);
    expect(update['blockMode'], 'null_ip', reason: '整份表单原样带上');
    expect(find.text(l10n.desktopFilterEngineOffMessage), findsOneWidget);
    expect(
      tester.widget<DashboardSwitch>(inSummary(find.byType(DashboardSwitch))).value,
      isFalse,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存应答模式提交模式、阻断地址与周期', (tester) async {
    final backend = await pumpConfig(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inMode(find.text(l10n.desktopFilterModeNxdomain)));
    final fields = inMode(find.byType(TextFormField));
    await tester.enterText(fields.at(0), '127.0.0.1');
    await tester.enterText(fields.at(1), '::1');
    await tester.enterText(fields.at(2), '6');
    await tapAt(tester, inMode(find.text(l10n.desktopFilterModeSave)).first);

    final update = backend.filterConfigUpdates.single;
    expect(update['blockMode'], 'nxdomain');
    expect(update['blockingIPv4'], '127.0.0.1');
    expect(update['blockingIPv6'], '::1');
    expect(update['updateIntervalHours'], 6);
    expect(find.text(l10n.desktopFilterModeSaved), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非法周期或空地址不提交', (tester) async {
    final backend = await pumpConfig(tester);
    final l10n = l10nOf(tester);

    final fields = inMode(find.byType(TextFormField));
    await tester.enterText(fields.at(2), '0');
    await tapAt(tester, inMode(find.text(l10n.desktopFilterModeSave)).first);

    expect(backend.filterConfigUpdates, isEmpty);
    expect(find.text(l10n.desktopFilterModeInvalid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('暂停按所选时长提交，恢复时不带时长', (tester) async {
    final backend = await pumpConfig(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inPause(find.text(l10n.desktopFilterPauseAction)));
    expect(backend.filterPauseRequests.single, {
      'paused': true,
      'durationSec': 1800,
    });
    expect(
      inPause(find.text(l10n.desktopFilterPauseActiveTitle)),
      findsOneWidget,
    );
    await clearMessages(tester);

    await tapAt(tester, inPause(find.text(l10n.desktopFilterPauseResume)));
    expect(backend.filterPauseRequests.last, {'paused': false});
    expect(find.text(l10n.desktopFilterPauseAction), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('高级开关各自提交，伪应答地址按行保存', (tester) async {
    final backend = await pumpConfig(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inAdvanced(find.byType(DashboardSwitch)).at(0));
    expect(backend.filterConfigUpdates.last['filterResponse'], isTrue);
    await clearMessages(tester);

    await tapAt(tester, inAdvanced(find.byType(DashboardSwitch)).at(2));
    expect(backend.filterConfigUpdates.last['bogusNxDomain'], isTrue);
    await clearMessages(tester);

    await tester.enterText(
      inAdvanced(find.byType(TextField)),
      ' 0.0.0.0/8 \n\n127.0.0.0/8\n',
    );
    await tapAt(tester, inAdvanced(find.text(l10n.desktopFilterAdvancedBogusSave)));

    expect(backend.filterConfigUpdates.last['bogusNxDomainNetworks'], [
      '0.0.0.0/8',
      '127.0.0.0/8',
    ]);
    expect(
      find.text(l10n.desktopFilterAdvancedBogusSaved(2)),
      findsOneWidget,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可疑地址给出提示但仍交给服务判定', (tester) async {
    await pumpConfig(
      tester,
      backend: FakeDesktopBackend(
        filterConfig: filterConfigPayload(
          bogusNxDomain: true,
          bogusNxDomainNetworks: const ['127.0.0.0/8'],
        ),
      ),
    );
    final l10n = l10nOf(tester);

    await tester.enterText(inAdvanced(find.byType(TextField)), 'not-an-ip');
    await tester.pumpAndSettle();

    expect(
      find.text(
        l10n.desktopFilterAdvancedBogusSuspicious('not-an-ip'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('写被拒时说明原因且开关保持服务端值', (tester) async {
    final backend = await pumpConfig(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tapAt(tester, inSummary(find.byType(DashboardSwitch)));

    expect(
      find.text(l10n.desktopFilterConfigSaveFailed('write rejected')),
      findsOneWidget,
    );
    expect(
      tester.widget<DashboardSwitch>(inSummary(find.byType(DashboardSwitch))).value,
      isTrue,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗下三张卡片单列且不横向溢出', (tester) async {
    await pumpConfig(tester, size: const Size(390, 844));
    expect(find.byType(FilterModeCard), findsOneWidget);
    expect(find.byType(FilterPauseCard), findsOneWidget);
    expect(find.byType(FilterAdvancedCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
