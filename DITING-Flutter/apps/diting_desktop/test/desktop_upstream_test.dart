// Desktop hub upstream page (docs/development/flutter-desktop-ui.md step 4): the console's
// scheduling modes, configured servers, bootstrap DNS, split routes and independent fallback chain.
// Every number and name must come from the service; a save posts the whole config and re-reads it.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_upstream_models.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/hub/desktop_upstream_page.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpUpstream(
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
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore(),
          ),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: const DesktopApp(initialLocation: DesktopUpstreamPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopUpstreamPage)).l10n;

  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(CommonDialog), matching: matching);

  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    // Center it, not flush to the top: the scaffold's bar floats over the page and would eat a tap
    // on a control that ensureVisible parked at y=0.
    await Scrollable.ensureVisible(
      tester.element(finder),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  test('缺省的响应码回退用服务默认，显式空数组保持为空', () {
    final absent = DesktopUpstreamConfig.fromJson({'mode': 'smart_prediction'});
    expect(absent.fallbackOnRcode, DesktopUpstreamConfig.defaultFallbackRcodes);
    expect(absent.fallbackOnError, isTrue);
    expect(absent.effectiveFallbackTimeoutMs, 2000);
    expect(absent.bootstrapEnabled, isTrue);

    final explicit = DesktopUpstreamConfig.fromJson({
      'fallbackOnRcode': <int>[],
      'fallbackOnError': false,
      'fallbackTimeoutMs': 1500,
    });
    expect(explicit.fallbackOnRcode, isEmpty);
    expect(explicit.fallbackOnError, isFalse);
    expect(explicit.effectiveFallbackTimeoutMs, 1500);
  });

  test('提交整表：模式大写，空回退链也显式发送', () {
    final config = DesktopUpstreamConfig.fromJson(upstreamPayload());
    final body = config.toJson();
    expect(body['mode'], 'PRIMARY_BACKUP');
    expect(body['providers'], hasLength(2));
    expect(body['fallbackProviders'], isEmpty);
    expect(body['bootstrap'], isA<Map<String, Object?>>());
    expect(body['fallbackOnRcode'], [2, 5]);
  });

  testWidgets('窄窗单列铺开，滚到底也不溢出', (tester) async {
    await pumpUpstream(tester, size: const Size(390, 844));

    expect(find.byType(DesktopUpstreamPage), findsOneWidget);
    // One column: the Bootstrap card sits above the fallback card instead of beside it.
    final bootstrap = tester.getTopLeft(
      find.text(l10nOf(tester).desktopUpstreamBootstrapTitle),
    );
    final fallback = tester.getTopLeft(
      find.text(l10nOf(tester).desktopUpstreamFallbackTitle),
    );
    expect(fallback.dy, greaterThan(bootstrap.dy));

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务器、Bootstrap、分流与回退都显示服务返回的内容', (tester) async {
    final backend = await pumpUpstream(
      tester,
      backend: FakeDesktopBackend(
        upstream: upstreamPayload(
          conditionalRoutes: {'*.corp.internal': '10.0.0.1:53'},
        ),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopUpstreamPage), findsOneWidget);
    expect(find.text(l10n.desktopUpstreamModeTitle), findsOneWidget);
    for (final label in [
      l10n.desktopUpstreamModeSingle,
      l10n.desktopUpstreamModeBackup,
      l10n.desktopUpstreamModeRace,
      l10n.desktopUpstreamModeSmart,
    ]) {
      // The current mode also appears in the header chip.
      expect(find.text(label), findsWidgets);
    }

    expect(find.text(l10n.desktopUpstreamNodesCount(2)), findsOneWidget);
    expect(find.text('AliDNS (DoT)'), findsOneWidget);
    expect(find.text('dns.alidns.com:853'), findsOneWidget);
    expect(find.text('Cloudflare (DoH)'), findsOneWidget);
    expect(find.text('https://cloudflare-dns.com/dns-query'), findsOneWidget);
    expect(find.text('DoT'), findsOneWidget);
    expect(find.text('DoH'), findsOneWidget);
    expect(find.text(l10n.desktopUpstreamPinSet), findsOneWidget);

    expect(find.text(l10n.desktopUpstreamBootstrapOn), findsOneWidget);
    expect(find.text('AliDNS'), findsOneWidget);
    expect(find.text('223.5.5.5:53'), findsOneWidget);
    expect(find.text('DNSPod'), findsOneWidget);

    expect(find.text('*.corp.internal'), findsOneWidget);
    expect(find.text('10.0.0.1:53'), findsOneWidget);
    expect(find.text(l10n.desktopUpstreamFallbackOff), findsOneWidget);
    expect(backend.has('/api/v1/upstream/configure'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换调度模式提交整份配置', (tester) async {
    final backend = await pumpUpstream(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text(l10n.desktopUpstreamModeRace));

    final body = backend.upstreamUpdates.last;
    expect(body['mode'], 'PARALLEL_RACE');
    expect(body['providers'], isA<List<Object?>>());
    expect((body['providers'] as List).length, 2);
    expect(body['bootstrap'], isA<Map<String, Object?>>());
    // An explicit empty fallback chain means "off"; omitting it would keep the old chain.
    expect(body['fallbackProviders'], isEmpty);
    expect(body['fallbackOnRcode'], [2, 5]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('添加服务器把新节点写进 POST', (tester) async {
    final backend = await pumpUpstream(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byTooltip(l10n.desktopUpstreamAdd));
    expect(find.byType(CommonDialog), findsOneWidget);
    await tester.enterText(
      inDialog(
        find.widgetWithText(TextFormField, l10n.desktopUpstreamName),
      ),
      'Quad9',
    );
    await tester.enterText(
      inDialog(
        find.widgetWithText(TextFormField, l10n.desktopUpstreamAddress),
      ),
      '9.9.9.9:53',
    );
    await tester.pumpAndSettle();
    await tapAt(tester, inDialog(find.text(l10n.commonSave)));

    final providers = backend.upstreamUpdates.last['providers'] as List;
    expect(providers, hasLength(3));
    final added = (providers.last as Map).cast<String, Object?>();
    expect(added['id'], 'Quad9');
    expect(added['server'], '9.9.9.9:53');
    expect(added['protocol'], 'DOT');
    expect(find.byType(CommonDialog), findsNothing);
  });

  testWidgets('删除服务器要确认，且不允许删到零个', (tester) async {
    final backend = await pumpUpstream(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byTooltip(l10n.commonDelete).first);
    expect(find.text(l10n.desktopUpstreamDeleteTitle), findsOneWidget);
    expect(
      find.text(l10n.desktopUpstreamDeleteBody('AliDNS (DoT)')),
      findsOneWidget,
    );
    await tapAt(tester, inDialog(find.text(l10n.commonDelete)));

    final providers = backend.upstreamUpdates.last['providers'] as List;
    expect(providers, hasLength(1));
    expect((providers.single as Map)['id'], 'Cloudflare (DoH)');

    await pumpUpstream(
      tester,
      backend: FakeDesktopBackend(
        upstream: upstreamPayload(
          providers: const [
            {
              'id': 'Only',
              'protocol': 'DOT',
              'server': 'dns.alidns.com:853',
            },
          ],
        ),
      ),
    );
    await tapAt(tester, find.byTooltip(l10n.commonDelete).first);
    expect(find.text(l10n.desktopUpstreamKeepOne), findsOneWidget);
    await tapAt(tester, find.text(l10n.commonConfirm));
    expect(find.text(l10n.desktopUpstreamKeepOne), findsNothing);
  });

  testWidgets('Bootstrap 开关与分流规则各自即时提交', (tester) async {
    final backend = await pumpUpstream(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is DashboardSwitch &&
            widget.semanticLabel == l10n.desktopUpstreamBootstrapTitle,
      ),
    );
    final bootstrap =
        backend.upstreamUpdates.last['bootstrap'] as Map<String, Object?>;
    expect(bootstrap['enabled'], isFalse);
    expect((bootstrap['servers'] as List), hasLength(2));

    await tapAt(tester, find.byTooltip(l10n.desktopUpstreamRoutesAdd));
    final fields = inDialog(find.byType(TextFormField));
    await tester.enterText(fields.at(0), '*.Corp.Internal');
    await tester.enterText(fields.at(1), '10.0.0.1:53');
    await tester.pumpAndSettle();
    await tapAt(tester, inDialog(find.text(l10n.commonSave)));

    expect(
      backend.upstreamUpdates.last['conditionalRoutes'],
      {'*.corp.internal': '10.0.0.1:53'},
    );
  });

  testWidgets('回退链开关、超时与响应码都写进同一份配置', (tester) async {
    final backend = await pumpUpstream(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is DashboardSwitch &&
            widget.semanticLabel == l10n.desktopUpstreamFallbackTitle,
      ),
    );
    final enabled = backend.upstreamUpdates.last['fallbackProviders'] as List;
    expect(enabled, hasLength(1));
    expect((enabled.single as Map)['protocol'], 'DOT');

    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        l10n.desktopUpstreamFallbackTimeout,
      ),
      '5000',
    );
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(backend.upstreamUpdates.last['fallbackTimeoutMs'], 5000);

    await tapAt(tester, find.text('NOTIMP'));
    expect(backend.upstreamUpdates.last['fallbackOnRcode'], contains(4));
  });

  testWidgets('延迟测试把协议与地址发给服务并显示结果', (tester) async {
    final backend = await pumpUpstream(tester);

    await tapAt(tester, find.text(l10nOf(tester).desktopUpstreamTest).first);

    expect(backend.probes.last['protocol'], 'DOT');
    expect(backend.probes.last['server'], 'dns.alidns.com:853');
    expect(find.text('23.5 ms'), findsOneWidget);
  });

  testWidgets('保存失败时说明服务给的错误并保留表单', (tester) async {
    final backend = FakeDesktopBackend()..rejectWrites = true;
    await pumpUpstream(tester, backend: backend);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text(l10n.desktopUpstreamModeSmart));

    expect(find.byType(CommonDialog), findsNothing);
    expect(
      find.text(l10n.desktopUpstreamSaveFailed('write rejected')),
      findsOneWidget,
    );
    // The service never accepted the change, so the mode chip still shows the old one.
    expect(find.text(l10n.desktopUpstreamModeBackup), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('粘贴印章回填协议、地址与 URL', (tester) async {
    final backend = await pumpUpstream(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byTooltip(l10n.desktopUpstreamAdd));
    final fields = inDialog(find.byType(TextFormField));
    await tester.enterText(fields.first, 'sdns://AQcAAAAAAAA');
    await tester.pumpAndSettle();
    await tapAt(tester, inDialog(find.text(l10n.desktopUpstreamStampParse)));

    expect(find.text(l10n.desktopUpstreamStampParsed('DoH')), findsOneWidget);
    expect(inDialog(find.text('https://dns.alidns.com/dns-query')), findsWidgets);

    await tapAt(tester, inDialog(find.text(l10n.commonSave)));
    final providers = backend.upstreamUpdates.last['providers'] as List;
    final added = (providers.last as Map).cast<String, Object?>();
    expect(added['protocol'], 'DOH');
    expect(added['server'], 'dns.alidns.com');
    expect(added['url'], 'https://dns.alidns.com/dns-query');
  });
}
