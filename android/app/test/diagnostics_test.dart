// Network-tool judging rules and panels: host sanitizing, a sparse `fromMap`,
// and every probe state.

import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/pages/tools/tools_page.dart';
import 'package:diting_android/state/diagnostics_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';
import 'support/test_hooks.dart';

void main() {
  group('网络工具面板', _diagnostics);
}

void _diagnostics() {
  installGlobalTestHooks();

  group('host 清洗', () {
    test('去 scheme / 路径 / userinfo / 端口', () {
      expect(
        sanitizeProbeHost('https://user:pass@example.com:8443/path?q=1'),
        'example.com',
      );
      expect(sanitizeProbeHost('http://example.com'), 'example.com');
      expect(sanitizeProbeHost('example.com/path'), 'example.com');
      expect(sanitizeProbeHost('example.com?q=1'), 'example.com');
      expect(sanitizeProbeHost('example.com#frag'), 'example.com');
      expect(sanitizeProbeHost('  example.com  '), 'example.com');
    });

    test('方括号 IPv6 取括注内容', () {
      expect(sanitizeProbeHost('[::1]:53'), '::1');
      expect(sanitizeProbeHost('[2001:db8::1]'), '2001:db8::1');
      expect(sanitizeProbeHost('https://[::1]:8080/x'), '::1');
      expect(sanitizeProbeHost('[::1'), '[::1');
    });

    test('裸 IPv6 不被端口规则误伤', () {
      expect(sanitizeProbeHost('2001:db8::1'), '2001:db8::1');
      expect(sanitizeProbeHost('::1'), '::1');
      expect(sanitizeProbeHost('fe80::1'), 'fe80::1');
    });
  });

  group('fromMap 缺字段容错', () {
    test('PingSummary 空 map 得到失败形态', () {
      final summary = PingSummary.fromMap(const {});

      expect(summary.target, '');
      expect(summary.transmitted, 0);
      expect(summary.received, 0);
      expect(summary.lossPercent, 100);
      expect(summary.success, isFalse);
      expect(summary.replies, isEmpty);
      expect(summary.measuredWithFallback, isFalse);
      expect(summary.minMs, isNull);
    });

    test('TraceResult / DnsLookupResult 空 map 不抛', () {
      final trace = TraceResult.fromMap(const {});
      expect(trace.hops, isEmpty);
      expect(trace.success, isFalse);
      expect(trace.cancelled, isFalse);

      final lookup = DnsLookupResult.fromMap(const {});
      expect(lookup.answers, isEmpty);
      expect(lookup.source, 'error');
      expect(lookup.success, isFalse);
      expect(lookup.elapsedMs, 0);
    });
  });

  group('runner 守卫', () {
    test('平台异常转成可读失败结果，不冒到调用方', () async {
      const runner = UnavailableDiagnosticsRunner();

      expect((await runner.ping('example.com')).success, isFalse);
      expect((await runner.traceRoute('example.com')).success, isFalse);
      expect((await runner.lookupDns('example.com')).error, isNotNull);
      expect((await runner.networkInfo()).interfaceName, '');
    });
  });

  group('Ping 面板', () {
    Future<void> openPing(WidgetTester tester) async {
      await tester.tap(find.text('Ping 测试'));
      await tester.pumpAndSettle();
    }

    Future<void> pumpPanel(
      WidgetTester tester,
      DiagnosticsRunner runner,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [diagnosticsRunnerProvider.overrideWithValue(runner)],
          child: const AppHost(child: ToolsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await openPing(tester);
    }

    testWidgets('成功态渲染 min/avg/max、丢包与逐条 reply', (tester) async {
      await pumpPanel(tester, _FakeRunner(pingResult: _successfulPing));

      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/x',
      );
      await tester.pump();
      await tester.tap(find.text('开始 Ping'));
      await tester.pumpAndSettle();

      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('93.184.216.34'), findsOneWidget);
      expect(find.text('4 / 4'), findsOneWidget);
      expect(find.text('0.0 %'), findsOneWidget);
      expect(find.text('10.0 ms / 12.5 ms / 18.0 ms'), findsOneWidget);
      // `PageBody` builds lazily, so `jumpTo(maxScrollExtent)` sees a stale bound; drag instead
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.text('目标'), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(find.text('第 1 个包'), findsOneWidget);
      expect(find.text('第 4 个包'), findsOneWidget);
      expect(find.textContaining('TCP 回退测量'), findsNothing);
    });

    testWidgets('空目标不发起探测，直接给输入校验文案', (tester) async {
      final runner = _FakeRunner(pingResult: _successfulPing);
      await pumpPanel(tester, runner);

      await tester.tap(find.text('开始 Ping'));
      await tester.pumpAndSettle();

      expect(find.text('请输入探测目标'), findsOneWidget);
      expect(runner.pingCalls, isEmpty);
    });
  });

  group('viaTunnel 开关落盘', () {
    testWidgets('写 network_tools_settings 的 ping_via_tunnel', (tester) async {
      final store = MemoryLegacyPrefsStore();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            legacyPrefsStoreProvider.overrideWithValue(store),
            diagnosticsRunnerProvider.overrideWithValue(
              _FakeRunner(pingResult: _successfulPing),
            ),
          ],
          child: const AppHost(child: ToolsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ping 测试'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('通过 Go 隧道解析'));
      await tester.pumpAndSettle();

      expect(
        store.read(networkToolsContainer, pingViaTunnelKey),
        isTrue,
        reason: '开关必须落到 network_tools_settings 容器的 ping_via_tunnel 键',
      );
    });
  });

  group('DNS 解析的服务器模式', () {
    Future<void> openDns(
      WidgetTester tester,
      _FakeRunner runner, {
      LegacyPrefsStore? store,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (store != null)
              legacyPrefsStoreProvider.overrideWithValue(store),
            diagnosticsRunnerProvider.overrideWithValue(runner),
          ],
          child: const AppHost(child: ToolsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('DNS 解析'));
      await tester.pumpAndSettle();
    }

    testWidgets('默认跟随系统：不向通道传服务器', (tester) async {
      final runner = _FakeRunner(pingResult: _successfulPing);
      await openDns(tester, runner);

      await tester.enterText(find.byType(TextField).first, 'example.com');
      await tester.pump();
      await tester.tap(find.text('开始查询'));
      await tester.pumpAndSettle();

      expect(runner.dnsLookupServers, [null]);
      expect(find.text('跟随系统'), findsNWidgets(2));
    });

    testWidgets('切到自定义并填 IP 后，服务器被传给通道', (tester) async {
      final runner = _FakeRunner(pingResult: _successfulPing);
      await openDns(tester, runner);

      expect(find.text('跟随系统'), findsOneWidget);
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'example.com');
      await tester.enterText(find.byType(TextField).at(1), '1.1.1.1');
      await tester.pump();
      await tester.tap(find.text('开始查询'));
      await tester.pumpAndSettle();

      expect(runner.dnsLookupServers, [
        '1.1.1.1',
      ], reason: '自定义服务器必须原样传到原生侧，否则测的还是系统解析器');
    });

    testWidgets('开启隧道后隐藏服务器选择器（此时由隧道决定）', (tester) async {
      final runner = _FakeRunner(pingResult: _successfulPing);
      await openDns(
        tester,
        runner,
        store: MemoryLegacyPrefsStore({
          networkToolsContainer: {dnsLookupViaTunnelKey: true},
        }),
      );

      expect(find.text('自定义'), findsNothing);
      expect(find.text('跟随系统'), findsNothing);
    });
  });
}

class _FakeRunner implements DiagnosticsRunner {
  _FakeRunner({required this.pingResult});

  final PingSummary pingResult;
  final List<String> pingCalls = [];

  final List<String?> dnsLookupServers = [];

  @override
  Future<PingSummary> ping(
    String target, {
    int count = 4,
    int timeoutSeconds = 3,
  }) async {
    pingCalls.add(target);
    return pingResult;
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
  }) async {
    dnsLookupServers.add(server);
    return DnsLookupResult(
      domain: domain,
      source: 'upstream',
      answers: const [DnsAnswer(recordType: 'A', value: '1.2.3.4', ttl: 60)],
      elapsedMs: 8,
    );
  }

  @override
  Future<NetworkInfoSnapshot> networkInfo() async => const NetworkInfoSnapshot(
    interfaceName: 'wlan0',
    localIpv4: '192.168.1.20',
    privateDns: 'off',
    vpnActive: false,
  );
}

const _successfulPing = PingSummary(
  target: 'example.com',
  resolvedAddress: '93.184.216.34',
  addressFamily: 'IPv4',
  transmitted: 4,
  received: 4,
  lossPercent: 0,
  minMs: 10,
  avgMs: 12.5,
  maxMs: 18,
  jitterMs: 2.5,
  success: true,
  replies: [
    PingReply(sequence: 1, elapsedMs: 10, ttl: 57),
    PingReply(sequence: 2, elapsedMs: 12.5, ttl: 57),
    PingReply(sequence: 3, elapsedMs: 12, ttl: 57),
    PingReply(sequence: 4, elapsedMs: 18, ttl: 57),
  ],
);
