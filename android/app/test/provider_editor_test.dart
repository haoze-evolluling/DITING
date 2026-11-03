// The custom-provider dialog asks for host and port on separate lines and pre-fills the protocol's
// default port (plain DNS 53, DoT 853), which is what reaches `user_providers_json`.

import 'dart:convert';

import 'package:diting_android/pages/hub/provider_management_page.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    MemoryLegacyPrefsStore store,
  ) async {
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
}
