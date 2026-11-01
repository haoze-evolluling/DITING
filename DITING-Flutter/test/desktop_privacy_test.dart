// Desktop hub security and privacy (docs/development/flutter-desktop-ui.md step 4): the
// protocol-hardening switches, the ECS policy and the rebinding / hosts defences. Values come from
// `/status`; each switch patches its own endpoint and the page re-reads.

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/data/api/desktop_privacy_models.dart';
import 'package:diting/desktop/pages/hub/desktop_privacy_page.dart';
import 'package:diting/desktop/pages/hub/widgets/privacy_defence_card.dart';
import 'package:diting/desktop/pages/hub/widgets/privacy_ecs_card.dart';
import 'package:diting/desktop/pages/hub/widgets/privacy_protocol_card.dart';
import 'package:diting/desktop/widgets/desktop_picker.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpPrivacy(
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
        child: const DesktopApp(initialLocation: DesktopPrivacyPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopPrivacyPage)).l10n;

  Finder inProtocol(Finder matching) => find.descendant(
    of: find.byType(PrivacyProtocolCard),
    matching: matching,
  );
  Finder inEcs(Finder matching) =>
      find.descendant(of: find.byType(PrivacyEcsCard), matching: matching);
  Finder inDefence(Finder matching) => find.descendant(
    of: find.byType(PrivacyDefenceCard),
    matching: matching,
  );

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

  test('缺字段按默认值解析，隐私子集只带协议字段', () {
    final config = DesktopPrivacyConfig.fromJson(const {});
    expect(config.enableEde, isTrue);
    expect(config.blockPrivatePtr, isTrue);
    expect(config.blockUnqualified, isFalse);
    expect(config.ecsEnabled, isTrue);
    expect(config.rebindAllowedDomains, isEmpty);
    expect(config.hostsTtl, 0);
    expect(config.effectiveAnyMode, 'notimp');

    final parsed = DesktopPrivacyConfig.fromJson(const {
      'dns': {'blockANY': true, 'blockANYMode': 'rfc8482', 'ednsPadding': 468},
      'rebind': {'enabled': false, 'allowedDomains': ['.lan']},
    });
    expect(parsed.effectiveAnyMode, 'rfc8482');
    expect(parsed.rebindEnabled, isFalse);
    expect(parsed.rebindAllowedDomains, ['.lan']);
    final json = parsed.privacyJson();
    expect(json['blockANY'], isTrue);
    expect(json['blockANYMode'], 'rfc8482');
    expect(json['ednsPadding'], 468);
    expect(json.containsKey('ecsEnabled'), isFalse);
  });

  testWidgets('页面显示服务返回的协议开关与防御状态', (tester) async {
    await pumpPrivacy(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopPrivacyProtocolTitle), findsOneWidget);
    expect(find.text(l10n.desktopPrivacyEcsTitle), findsOneWidget);
    expect(find.text(l10n.desktopPrivacyDefenceTitle), findsOneWidget);
    expect(inProtocol(find.byType(DashboardSwitch)), findsNWidgets(6));
    expect(
      tester.widget<DashboardSwitch>(
        inProtocol(find.byType(DashboardSwitch)).first,
      ).value,
      isTrue,
      reason: 'EDE 默认开启',
    );
    expect(
      find.text(l10n.desktopPrivacyRebindCount(2)),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopPrivacyHostsTtl(60)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('协议开关各自提交隐私子集并回读', (tester) async {
    final backend = await pumpPrivacy(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inProtocol(find.byType(DashboardSwitch)).first);

    final update = backend.privacyUpdates.single;
    expect(update['enableEDE'], isFalse);
    expect(update['blockPrivatePTR'], isTrue, reason: '整份隐私子集原样带上');
    expect(update['blockANYMode'], 'notimp');
    expect(find.text(l10n.desktopPrivacyEdeOff), findsOneWidget);
    await clearMessages(tester);

    await tapAt(tester, inProtocol(find.byType(DashboardSwitch)).at(2));
    expect(backend.unqualifiedUpdates.single['blockUnqualified'], isTrue);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ANY 最小化选择应答形式', (tester) async {
    final backend = await pumpPrivacy(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inProtocol(find.byType(DashboardSwitch)).at(4));
    expect(backend.privacyUpdates.last['blockANY'], isTrue);
    await clearMessages(tester);

    await tapAt(tester, find.text(l10n.desktopPrivacyAnyModeRfc));
    expect(backend.privacyUpdates.last['blockANYMode'], 'rfc8482');
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EDNS 填充大小通过选择器提交', (tester) async {
    final backend = await pumpPrivacy(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inProtocol(find.byType(DesktopPicker)));
    await tapAt(tester, find.text(l10n.desktopPrivacyPaddingValue(468)));

    expect(backend.privacyUpdates.single['ednsPadding'], 468);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ECS 开关与自定义子网各自提交', (tester) async {
    final backend = await pumpPrivacy(tester);

    await tapAt(tester, inEcs(find.byType(DashboardSwitch)).at(1));
    expect(backend.ecsUpdates.single['stripECS'], isFalse);
    await clearMessages(tester);

    await tester.enterText(
      inEcs(find.byType(TextFormField)),
      ' 203.0.113.0/24 ',
    );
    await tapAt(
      tester,
      inEcs(find.byType(FilledButton)).first,
    );
    expect(backend.ecsUpdates.last['customSubnet'], '203.0.113.0/24');
    expect(backend.ecsUpdates.last['enabled'], isTrue);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重绑定白名单按行保存', (tester) async {
    final backend = await pumpPrivacy(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text(l10n.desktopPrivacyRebindAllowlist));
    await tester.enterText(
      find.descendant(
        of: find.byType(CommonDialog),
        matching: find.byType(TextField),
      ),
      ' localhost \n\n .lan\n .local \n',
    );
    await tapAt(tester, find.text(l10n.desktopPrivacyRebindDialogSave));

    expect(backend.rebindUpdates.single['allowedDomains'], [
      'localhost',
      '.lan',
      '.local',
    ]);
    expect(find.text(l10n.desktopPrivacyRebindCount(3)), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hosts 联动系统开关提交', (tester) async {
    final backend = await pumpPrivacy(tester);

    await tapAt(tester, inDefence(find.byType(DashboardSwitch)).last);

    final update = backend.hostsUpdates.single;
    expect(update['useSystemHost'], isFalse);
    expect(update['enabled'], isTrue);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写被拒时说明原因且开关保持服务端值', (tester) async {
    final backend = await pumpPrivacy(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tapAt(tester, inProtocol(find.byType(DashboardSwitch)).first);

    expect(
      find.text(l10n.desktopPrivacySaveFailed('write rejected')),
      findsOneWidget,
    );
    expect(
      tester.widget<DashboardSwitch>(
        inProtocol(find.byType(DashboardSwitch)).first,
      ).value,
      isTrue,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗下三张卡片单列且不横向溢出', (tester) async {
    await pumpPrivacy(tester, size: const Size(390, 844));
    expect(find.byType(PrivacyProtocolCard), findsOneWidget);
    expect(find.byType(PrivacyEcsCard), findsOneWidget);
    expect(find.byType(PrivacyDefenceCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
