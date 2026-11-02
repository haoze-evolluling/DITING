// Desktop hub encrypted DNS server (desktop parity): listeners,
// certificate, DDR, reverse-proxy trust and the mobile profile. Every value comes from
// `/encrypted/dns/status`; each write adopts the whole status the service answers with.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/hub/desktop_encrypted_page.dart';
import 'package:diting_desktop/pages/hub/widgets/encrypted_cert_card.dart';
import 'package:diting_desktop/pages/hub/widgets/encrypted_extras_card.dart';
import 'package:diting_desktop/pages/hub/widgets/encrypted_listeners_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpEncrypted(
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
        child: const DesktopApp(initialLocation: DesktopEncryptedPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopEncryptedPage)).l10n;

  Finder inListeners(Finder matching) => find.descendant(
    of: find.byType(EncryptedListenersCard),
    matching: matching,
  );
  Finder inCert(Finder matching) =>
      find.descendant(of: find.byType(EncryptedCertCard), matching: matching);
  Finder inExtras(Finder matching) => find.descendant(
    of: find.byType(EncryptedExtrasCard),
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

  test('缺字段按零值解析，端口回落到默认值', () {
    final config = DesktopEncryptedConfig.fromJson(const {});
    expect(config.enabled, isFalse);
    expect(config.effectiveDotPort, 853);
    expect(config.effectiveDohPort, 443);
    expect(config.effectiveDohPath, '/dns-query');
    expect(config.anyProtocol, isFalse);

    final status = DesktopEncryptedStatus.fromJson(const {
      'config': {'enabled': true, 'dotEnabled': true},
      'cert': {'loaded': true, 'selfSigned': true, 'daysRemaining': 12},
      'dohUrls': ['https://dns.lan/dns-query'],
    });
    expect(status.config.enabled, isTrue);
    expect(status.cert.selfSigned, isTrue);
    expect(status.cert.daysRemaining, 12);
    expect(status.dohUrls, hasLength(1));
    expect(DesktopCertInfo.fromJson(const {}).loaded, isFalse);
  });

  testWidgets('页面显示监听状态、证书摘要与 DoH 地址', (tester) async {
    await pumpEncrypted(tester);
    final l10n = l10nOf(tester);

    expect(
      inListeners(find.text(l10n.desktopEncryptedListenersTitle)),
      findsOneWidget,
    );
    expect(
      find.text(l10n.desktopEncryptedListening('192.168.1.10:853')),
      findsOneWidget,
    );
    expect(find.text('https://dns.lan/dns-query'), findsOneWidget);
    expect(find.text(l10n.desktopEncryptedCertSelfSigned), findsOneWidget);
    expect(
      find.text(l10n.desktopEncryptedCertFingerprint('AA:BB:CC')),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopEncryptedDdrTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('总开关与协议开关各自提交', (tester) async {
    final backend = await pumpEncrypted(tester);

    await tapAt(tester, inListeners(find.byType(DashboardSwitch)).first);
    expect(backend.encryptedUpdates.single['enabled'], isFalse);
    await clearMessages(tester);

    await tapAt(tester, inListeners(find.byType(DashboardSwitch)).at(3));
    expect(backend.encryptedUpdates.last['doqEnabled'], isTrue);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('监听参数由保存按钮提交，非法端口不提交', (tester) async {
    final backend = await pumpEncrypted(tester);
    final l10n = l10nOf(tester);

    final fields = inListeners(find.byType(TextFormField));
    await tester.enterText(fields.at(2), '0');
    await tapAt(
      tester,
      inListeners(find.text(l10n.desktopEncryptedSaveNetwork)),
    );
    expect(backend.encryptedUpdates, isEmpty);
    expect(find.text(l10n.desktopEncryptedPortInvalid), findsOneWidget);

    await tester.enterText(fields.at(2), '8853');
    await tapAt(
      tester,
      inListeners(find.text(l10n.desktopEncryptedSaveNetwork)),
    );
    final update = backend.encryptedUpdates.single;
    expect(update['dotPort'], 8853);
    expect(update['dohPort'], 443);
    expect(update['serverName'], 'dns.lan');
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('生成自签证书提交参数', (tester) async {
    final backend = await pumpEncrypted(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCert(find.text(l10n.desktopEncryptedCertGenerate)));
    final fields = find.descendant(
      of: find.byType(CommonDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'dns.home.lan');
    await tapAt(
      tester,
      find.text(l10n.desktopEncryptedCertGenerateConfirm),
    );

    final params = backend.certGenerations.single;
    expect(params['commonName'], 'dns.home.lan');
    expect(params['keyType'], 'ecdsa');
    expect(params['validDays'], 365);
    expect(find.text(l10n.desktopEncryptedCertGenerated), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开启 DDR 先确认，取消则不提交', (tester) async {
    final backend = await pumpEncrypted(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inExtras(find.byType(DashboardSwitch)).first);
    expect(find.text(l10n.desktopEncryptedDdrConfirmTitle), findsOneWidget);
    await tapAt(tester, find.text(l10n.commonCancel));
    expect(backend.encryptedUpdates, isEmpty);

    await tapAt(tester, inExtras(find.byType(DashboardSwitch)).first);
    await tapAt(tester, find.text(l10n.desktopEncryptedDdrConfirm));
    expect(backend.encryptedUpdates.single['ddrEnabled'], isTrue);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('反向代理开关与来源清单分别提交', (tester) async {
    final backend = await pumpEncrypted(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inExtras(find.byType(DashboardSwitch)).at(1));
    final enabled = backend.encryptedUpdates.single['reverseProxy'] as Map;
    expect(enabled['enabled'], isTrue);
    await clearMessages(tester);

    await tester.enterText(
      inExtras(find.byType(TextField)).first,
      ' 192.168.1.0/24 \n\n10.0.0.1\n',
    );
    await tapAt(
      tester,
      inExtras(find.text(l10n.desktopEncryptedProxySave)),
    );
    final proxy = backend.encryptedUpdates.last['reverseProxy'] as Map;
    expect(proxy['trustedSources'], ['192.168.1.0/24', '10.0.0.1']);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('证书过期时给出显著提示', (tester) async {
    await pumpEncrypted(
      tester,
      backend: FakeDesktopBackend(
        encrypted: encryptedPayload(certExpired: true),
      ),
    );
    final l10n = l10nOf(tester);

    expect(
      find.text(l10n.desktopEncryptedCertExpired),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗下两列改单列且不横向溢出', (tester) async {
    await pumpEncrypted(tester, size: const Size(390, 844));
    expect(find.byType(EncryptedListenersCard), findsOneWidget);
    expect(find.byType(EncryptedCertCard), findsOneWidget);
    expect(find.byType(EncryptedExtrasCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
