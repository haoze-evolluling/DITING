// The custom-provider dialog asks for host and port on separate lines and pre-fills the protocol's
// default port (plain DNS 53, DoT 853), which is what reaches `user_providers_json`.

import 'dart:convert';

import 'package:diting_android/data/native/dns_latency_bridge.dart';
import 'package:diting_android/pages/hub/provider_management_page.dart';
import 'package:diting_android/state/network_tools_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is only exported from `misc.dart`, not `flutter_riverpod.dart`.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

void main() {
  group('自定义服务商编辑弹窗', _editor);
}

void _editor() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MemoryLegacyPrefsStore emptyStore() {
    final store = MemoryLegacyPrefsStore({
      'dns_vpn_prefs': const {},
      'diting_express_prefs': const {},
      'diting_settings': const {'app_work_mode': 'normal'},
    });
    return store;
  }

  Future<void> openEditor(
    WidgetTester tester,
    MemoryLegacyPrefsStore store, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          ...overrides,
        ],
        child: const AppHost(child: ProviderManagementPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增 DNS 服务商'));
    await tester.pumpAndSettle();
  }

  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(AlertDialog), matching: matching);

  List<TextField> fields(WidgetTester tester) => tester
      .widgetList<TextField>(inDialog(find.byType(TextField)))
      .toList(growable: false);

  Map<String, Object?> savedProvider(MemoryLegacyPrefsStore store) =>
      (jsonDecode(store.read('dns_vpn_prefs', 'user_providers_json')! as String)
              as List)
          .single as Map<String, Object?>;

  testWidgets('普通 DNS 拆成地址与端口两行，端口默认 53', (tester) async {
    final store = emptyStore();
    await openEditor(tester, store);

    await tester.tap(inDialog(find.text('DNS')));
    await tester.pumpAndSettle();

    // 名称、地址、端口三个独立的输入框。
    final inputs = fields(tester);
    expect(inputs, hasLength(3));
    expect(inputs[1].decoration?.labelText, '地址');
    expect(inputs[2].decoration?.labelText, '端口');
    expect(inputs[2].controller?.text, '53');

    await tester.enterText(inDialog(find.byType(TextField)).at(0), '自建 DNS');
    await tester.enterText(inDialog(find.byType(TextField)).at(1), 'dns.example.com');
    await tester.tap(inDialog(find.text('保存')));
    await tester.pumpAndSettle();

    final saved = savedProvider(store);
    expect(saved['protocol'], 'DNS');
    expect(saved['host'], 'dns.example.com');
    expect(saved['port'], 53);
  });

  testWidgets('切到 DoT 时端口换成 853，DoH 只留一个 https 地址框', (tester) async {
    final store = emptyStore();
    await openEditor(tester, store);

    await tester.tap(inDialog(find.text('DoT')));
    await tester.pumpAndSettle();
    expect(fields(tester), hasLength(3));
    expect(fields(tester)[2].controller?.text, '853');

    await tester.tap(inDialog(find.text('DoH')));
    await tester.pumpAndSettle();
    expect(fields(tester), hasLength(2));
    expect(fields(tester)[1].decoration?.labelText, 'DoH 地址');
  });

  testWidgets('编辑已有 DoT 时回填地址与端口', (tester) async {
    final store = MemoryLegacyPrefsStore({
      'dns_vpn_prefs': {
        'user_providers_json': jsonEncode([
          {
            'id': 'user_1',
            'name': '自建 DoT',
            'protocol': 'DOT',
            'url': '',
            'host': 'dot.example',
            'port': 8853,
          },
        ]),
      },
      'diting_express_prefs': const {},
      'diting_settings': const {'app_work_mode': 'normal'},
    });
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
        child: const AppHost(child: ProviderManagementPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('DoT'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();

    final inputs = fields(tester);
    expect(inputs[1].controller?.text, 'dot.example');
    expect(inputs[2].controller?.text, '8853');
  });

  testWidgets('闪电按钮按填写的 DoH 地址回车测试，并显示可用与耗时', (tester) async {
    final store = emptyStore();
    final runner = _FakeRunner(
      const DnsLatencySample(
        providerId: 'draft',
        providerName: '自建 DoH',
        protocol: DnsLatencyProtocol.doh,
        elapsedMs: 42,
        success: true,
        attempts: 1,
        successCount: 1,
      ),
    );
    await openEditor(
      tester,
      store,
      overrides: [dnsLatencyRunnerProvider.overrideWithValue(runner)],
    );

    await tester.enterText(
      inDialog(find.byType(TextField)).at(1),
      'https://doh.example/dns-query',
    );
    await tester.tap(inDialog(find.byTooltip('测试该服务是否可用')));
    await tester.pumpAndSettle();

    final spec = runner.probed.single;
    expect(spec.protocol, DnsLatencyProtocol.doh);
    expect(spec.url, 'https://doh.example/dns-query');
    expect(spec.host, 'doh.example');
    expect(inDialog(find.text('可用 · 42 ms')), findsOneWidget);
  });

  testWidgets('普通 DNS 用地址与端口测试，失败时显示原因', (tester) async {
    final store = emptyStore();
    final runner = _FakeRunner(
      const DnsLatencySample(
        providerId: 'draft',
        providerName: '自建 DNS',
        protocol: DnsLatencyProtocol.dns,
        elapsedMs: 0,
        success: false,
        message: '无响应',
        attempts: 1,
        successCount: 0,
      ),
    );
    await openEditor(
      tester,
      store,
      overrides: [dnsLatencyRunnerProvider.overrideWithValue(runner)],
    );

    await tester.tap(inDialog(find.text('DNS')));
    await tester.pumpAndSettle();
    await tester.enterText(
      inDialog(find.byType(TextField)).at(1),
      'dns.example.com',
    );
    await tester.enterText(inDialog(find.byType(TextField)).at(2), '5353');
    await tester.tap(inDialog(find.byTooltip('测试该服务是否可用')));
    await tester.pumpAndSettle();

    final spec = runner.probed.single;
    expect(spec.protocol, DnsLatencyProtocol.dns);
    expect(spec.host, 'dns.example.com');
    expect(spec.port, 5353);
    expect(inDialog(find.text('不可用：无响应')), findsOneWidget);
  });

  testWidgets('地址不完整时不发请求，直接提示', (tester) async {
    final store = emptyStore();
    final runner = _FakeRunner(
      const DnsLatencySample(
        providerId: 'draft',
        providerName: 'draft',
        protocol: DnsLatencyProtocol.doh,
        elapsedMs: 1,
        success: true,
        attempts: 1,
        successCount: 1,
      ),
    );
    await openEditor(
      tester,
      store,
      overrides: [dnsLatencyRunnerProvider.overrideWithValue(runner)],
    );

    await tester.tap(inDialog(find.byTooltip('测试该服务是否可用')));
    await tester.pumpAndSettle();

    expect(runner.probed, isEmpty);
    expect(inDialog(find.text('DoH 地址需以 https:// 开头')), findsOneWidget);
  });
}

/// Answers every probe with one canned sample and records what reached the channel.
class _FakeRunner implements DnsLatencyRunner {
  _FakeRunner(this.sample);

  final DnsLatencySample sample;
  List<DnsLatencyProviderSpec> probed = const [];

  @override
  Future<bool> checkAvailable() async => true;

  @override
  Future<List<DnsLatencySample>> probe({
    required List<DnsLatencyProviderSpec> providers,
    required String domain,
    int attempts = 3,
  }) async {
    probed = providers;
    return [sample];
  }
}
