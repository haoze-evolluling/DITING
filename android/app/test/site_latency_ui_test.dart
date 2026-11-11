// Site latency card and detail page: nothing probes on open, and each category
// button touches only its own sites.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:diting_android/pages/home/dashboard/cards/site_latency_card.dart';
import 'package:diting_android/pages/home/dashboard/detail/site_latency_detail_page.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';
import 'support/test_hooks.dart';

void main() {
  group('站点测速卡', _siteLatencyCard);
  group('站点测速页', _siteLatencyPage);
}

void _siteLatencyCard() {
  // The card's auto-probe is skipped while the global flag is set, so turn it back off here.
  installGlobalTestHooks();

  testWidgets('自定义的四个站点测完后表头显示计数', (tester) async {
    debugDisableDashboardLiveUpdates = false;
    final runner = _CardRunner();
    final store = MemoryLegacyPrefsStore();
    LegacySettings(
      store,
    ).setDashboardSiteIds(const ['baidu', 'douyin', 'netease', 'duckduckgo']);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diagnosticsRunnerProvider.overrideWithValue(runner),
          legacyPrefsStoreProvider.overrideWithValue(store),
        ],
        child: const AppHost(child: SiteLatencyCard()),
      ),
    );
    await tester.pumpAndSettle();

    expect(runner.pingCalls, [
      'www.baidu.com',
      'www.douyin.com',
      'music.163.com',
      'duckduckgo.com',
    ]);
    expect(find.text('4 / 4 通畅'), findsOneWidget);
    expect(find.text('尚未测速'), findsNothing);
  });
}

class _CardRunner implements DiagnosticsRunner {
  final List<String> pingCalls = [];

  @override
  Future<PingSummary> ping(
    String target, {
    int count = 4,
    int timeoutSeconds = 3,
  }) async {
    pingCalls.add(target);
    return PingSummary(
      target: target,
      transmitted: count,
      received: count,
      lossPercent: 0,
      success: true,
      minMs: 1,
      avgMs: 1,
      maxMs: 2,
      jitterMs: 0,
    );
  }

  @override
  Future<TraceResult> traceRoute(String target, {int maxHops = 30}) async =>
      const TraceResult(target: '', hops: [], success: false);

  @override
  Future<DnsLookupResult> lookupDns(
    String domain, {
    bool viaTunnel = false,
    bool ipv4 = true,
    String? server,
  }) async => DnsLookupResult(
    domain: domain,
    source: 'upstream',
    answers: const [],
    elapsedMs: 0,
  );

  @override
  Future<NetworkInfoSnapshot> networkInfo() async => const NetworkInfoSnapshot(
    interfaceName: 'wlan0',
    localIpv4: '192.168.1.2',
    privateDns: '',
    vpnActive: false,
  );
}

/// Pins the two behaviours the detail page was rewritten for: nothing probes on open, and each
/// category has its own probe button that touches only its own sites.

void _siteLatencyPage() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PageRunner runner;

  setUp(() => runner = _PageRunner());

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diagnosticsRunnerProvider.overrideWithValue(runner),
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
        ],
        child: AppHost(child: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('进页面不会自动测速', (tester) async {
    await pumpPage(tester, const SiteLatencyDetailPage());

    expect(runner.pingCalls, isEmpty);
    expect(find.text('未测速'), findsOneWidget);
    expect(find.text('待测'), findsOneWidget);
    // The page lists every category, in enum order; the list is lazy, so walk it.
    final l10n = lookupAppL10n(const Locale('zh'));
    for (final category in SiteCategory.values) {
      await tester.dragUntilVisible(
        find.text(category.label(l10n)),
        find.byType(Scrollable).first,
        const Offset(0, -280),
      );
      expect(
        find.text(category.label(l10n)),
        findsWidgets,
        reason: category.label(l10n),
      );
    }
    expect(runner.pingCalls, isEmpty);
  });

  testWidgets('点某个分类的测速按钮只测该分类', (tester) async {
    await pumpPage(tester, const SiteLatencyDetailPage());

    final search = siteLatencyInCategory(SiteCategory.search);
    final l10n = lookupAppL10n(const Locale('zh'));
    final button = find.byTooltip(
      '测速${SiteCategory.search.label(l10n)}',
    );
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(runner.pingCalls, [for (final target in search) target.host]);
    expect(runner.pingCalls.length, lessThan(siteLatencyTargets.length));
    // The probed group reports its own tally, in the same '$alive / $total 通畅' shape the card
    // uses.
    expect(find.text('${search.length} / ${search.length} 通畅'), findsOneWidget);
  });
}

class _PageRunner implements DiagnosticsRunner {
  final List<String> pingCalls = [];

  @override
  Future<PingSummary> ping(
    String target, {
    int count = 4,
    int timeoutSeconds = 3,
  }) async {
    pingCalls.add(target);
    return PingSummary(
      target: target,
      transmitted: count,
      received: count,
      lossPercent: 0,
      success: true,
      minMs: 20,
      avgMs: 30,
      maxMs: 40,
      jitterMs: 2,
      resolvedAddress: '2408:8756::1',
      addressFamily: 'IPv6',
    );
  }

  @override
  Future<TraceResult> traceRoute(String target, {int maxHops = 30}) async =>
      const TraceResult(target: '', hops: [], success: false);

  @override
  Future<DnsLookupResult> lookupDns(
    String domain, {
    bool viaTunnel = false,
    bool ipv4 = true,
    String? server,
  }) async => DnsLookupResult(
    domain: domain,
    source: 'upstream',
    answers: const [],
    elapsedMs: 0,
  );

  @override
  Future<NetworkInfoSnapshot> networkInfo() async => const NetworkInfoSnapshot(
    interfaceName: 'wlan0',
    localIpv4: '192.168.1.2',
    privateDns: '',
    vpnActive: false,
  );
}
