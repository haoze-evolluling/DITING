// Desktop hub DNS64 page (docs/development/flutter-desktop-ui.md step 4): the synthesizer switch,
// the RFC 6052 prefix list and the protections the service applies. Every value must come from
// `/status`; a save posts the whole form and re-reads it, and a rejected write is reported.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_dns64_models.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/hub/desktop_dns64_page.dart';
import 'package:diting_desktop/pages/hub/widgets/dns64_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpDns64(
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
        child: const DesktopApp(initialLocation: DesktopDns64Page.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopDns64Page)).l10n;

  Finder inCard(Finder matching) =>
      find.descendant(of: find.byType(Dns64Card), matching: matching);

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

  test('缺字段按零值解析，空前缀回落到知名前缀', () {
    final empty = DesktopDns64Config.fromJson(const {});
    expect(empty.enabled, isFalse);
    expect(empty.prefixes, isEmpty);
    expect(empty.effectivePrefixes, [desktopDns64WellKnownPrefix]);
    expect(empty.prefixText, desktopDns64WellKnownPrefix);

    final parsed = DesktopDns64Config.fromJson(const {
      'enabled': true,
      'prefixes': [' 64:ff9b::/96 ', '', '2001:db8::/32'],
    });
    expect(parsed.enabled, isTrue);
    expect(parsed.prefixes, ['64:ff9b::/96', '2001:db8::/32']);
    expect(parsed.toJson()['enabled'], isTrue);
    expect(parsed.toJson()['prefixes'], ['64:ff9b::/96', '2001:db8::/32']);
  });

  test('文本按行拆分，去掉空白行与首尾空格', () {
    expect(desktopDns64ParsePrefixes(''), isEmpty);
    expect(
      desktopDns64ParsePrefixes(' 64:ff9b::/96 \n\n 2001:db8::/32\n'),
      ['64:ff9b::/96', '2001:db8::/32'],
    );
  });

  testWidgets('页面显示服务返回的开关与前缀', (tester) async {
    await pumpDns64(
      tester,
      backend: FakeDesktopBackend(
        dns64: dns64Payload(
          enabled: true,
          prefixes: const ['64:ff9b::/96', '2001:db8::/32'],
        ),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.byType(Dns64Card), findsOneWidget);
    expect(find.text(l10n.desktopDns64EngineOn), findsOneWidget);
    expect(
      inCard(find.byType(DashboardSwitch)),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(inCard(find.byType(TextField)));
    expect(field.controller?.text, '64:ff9b::/96\n2001:db8::/32');
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换开关提交整份配置并携带已输入前缀', (tester) async {
    final backend = await pumpDns64(
      tester,
      backend: FakeDesktopBackend(
        dns64: dns64Payload(enabled: false, prefixes: const ['64:ff9b::/96']),
      ),
    );
    final l10n = l10nOf(tester);

    await tester.enterText(
      inCard(find.byType(TextField)),
      '64:ff9b::/96\n2001:db8::/32',
    );
    await tapAt(tester, inCard(find.byType(DashboardSwitch)));

    final update = backend.dns64Updates.single;
    expect(update['enabled'], isTrue);
    expect(update['prefixes'], ['64:ff9b::/96', '2001:db8::/32']);
    expect(find.text(l10n.desktopDns64EngineOn), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存按钮提交去空行后的前缀并回显服务端值', (tester) async {
    final backend = await pumpDns64(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(
      inCard(find.byType(TextField)),
      ' 2001:db8::/32 \n\n',
    );
    await tapAt(tester, find.text(l10n.desktopDns64Save));

    final update = backend.dns64Updates.single;
    expect(update['enabled'], isFalse);
    expect(update['prefixes'], ['2001:db8::/32']);
    final field = tester.widget<TextField>(inCard(find.byType(TextField)));
    expect(field.controller?.text, '2001:db8::/32');
    expect(tester.takeException(), isNull);
  });

  testWidgets('标准前缀按钮只改本地草稿，不提交', (tester) async {
    final backend = await pumpDns64(
      tester,
      backend: FakeDesktopBackend(
        dns64: dns64Payload(prefixes: const ['2001:db8::/32']),
      ),
    );
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text(l10n.desktopDns64FillWellKnown));

    expect(backend.dns64Updates, isEmpty);
    final field = tester.widget<TextField>(inCard(find.byType(TextField)));
    expect(field.controller?.text, desktopDns64WellKnownPrefix);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写被拒时说明原因且开关保持服务端值', (tester) async {
    final backend = await pumpDns64(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tapAt(tester, inCard(find.byType(DashboardSwitch)));

    expect(
      find.text(l10n.desktopDns64SaveFailed('write rejected')),
      findsOneWidget,
    );
    final toggle = tester.widget<DashboardSwitch>(
      inCard(find.byType(DashboardSwitch)),
    );
    expect(toggle.value, isFalse);
    expect(find.text(l10n.desktopDns64EngineOff), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗下卡片不横向溢出', (tester) async {
    await pumpDns64(tester, size: const Size(390, 844));
    expect(find.byType(Dns64Card), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
