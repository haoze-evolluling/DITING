// Primary-backup order is persisted per id list and the engine tries providers in that order, so
// leaving and re-entering the page must keep what the user arranged instead of resetting to the
// catalog's first entry.

import 'dart:convert';

import 'package:diting_android/pages/hub/resolution_mode_page.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

void main() {
  group('依次尝试排序', _ordering);
}

MemoryLegacyPrefsStore _store(List<String> order) => MemoryLegacyPrefsStore({
  'dns_vpn_prefs': {
    'dns_resolution_mode': 'primary_backup',
    'preset_dns_service': 'DOH',
    'primary_backup_provider_ids': jsonEncode(order),
  },
  'diting_express_prefs': const {},
  'diting_settings': const {'app_work_mode': 'normal'},
});

void _ordering() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(
    WidgetTester tester,
    MemoryLegacyPrefsStore store, {
    Key? key,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
        child: AppHost(
          child: ResolutionModeConfigPage(key: key, modeId: 'backup'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Vertical position of a provider row; the smaller one is tried first.
  double topOf(WidgetTester tester, String name) =>
      tester.getTopLeft(find.text(name)).dy;

  List<String> persistedOrder(MemoryLegacyPrefsStore store) =>
      (jsonDecode(
                store.read('dns_vpn_prefs', 'primary_backup_provider_ids')!
                    as String,
              )
              as List)
          .cast<String>();

  Finder moveUpOf(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(ListItem)).last,
    matching: find.byTooltip('上移'),
  );

  testWidgets('进入页面按已保存的顺序排列，而不是目录顺序', (tester) async {
    await pumpPage(
      tester,
      _store([
        'preset_dnspod_doh',
        'preset_cloudflare_doh',
        'preset_alidns_doh',
      ]),
    );

    expect(topOf(tester, '腾讯云 DNSPod'), lessThan(topOf(tester, 'Cloudflare')));
    expect(
      topOf(tester, 'Cloudflare'),
      lessThan(topOf(tester, '阿里云')),
      reason: '阿里云不在首位时不能因目录顺序被提前',
    );
  });

  testWidgets('上移只与同协议的相邻项换位，并写回持久化顺序', (tester) async {
    final store = _store([
      'preset_dnspod_doh',
      'preset_alidns_doh',
      'preset_alidns_dns',
    ]);
    await pumpPage(tester, store);

    await tester.tap(moveUpOf('阿里云'));
    await tester.pumpAndSettle();

    expect(topOf(tester, '阿里云'), lessThan(topOf(tester, '腾讯云 DNSPod')));
    // DNS 组的项不参与 DoH 组的换位，槽位保持不动。
    expect(persistedOrder(store), [
      'preset_alidns_doh',
      'preset_dnspod_doh',
      'preset_alidns_dns',
    ]);
  });

  testWidgets('调整后退出再进入保持新顺序', (tester) async {
    final store = _store([
      'preset_dnspod_doh',
      'preset_cloudflare_doh',
      'preset_alidns_doh',
    ]);
    await pumpPage(tester, store);

    await tester.tap(moveUpOf('阿里云'));
    await tester.pumpAndSettle();

    // 重新挂载（模拟退出页面后再次进入）读同一份偏好。
    await pumpPage(tester, store, key: const ValueKey('reentry'));

    expect(topOf(tester, '腾讯云 DNSPod'), lessThan(topOf(tester, '阿里云')));
    expect(topOf(tester, '阿里云'), lessThan(topOf(tester, 'Cloudflare')));
  });
}
