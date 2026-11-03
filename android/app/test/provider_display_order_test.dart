// The service display page arranges the provider order; the provider picker ("选择竞速服务商")
// reuses that order, so it must be persisted and read back instead of following catalog order.

import 'dart:convert';

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/pages/hub/provider_management_page.dart';
import 'package:diting_android/pages/hub/provider_visibility_page.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

void main() {
  group('显示顺序计算', _order);
  group('服务商管理分组', _management);
}

void _order() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MemoryLegacyPrefsStore store({List<String> order = const []}) =>
      MemoryLegacyPrefsStore({
        'dns_vpn_prefs': {
          'dns_resolution_mode': 'parallel_race',
          'parallel_race_provider_ids':
              '["preset_alidns_doh","preset_dnspod_doh"]',
          if (order.isNotEmpty) 'provider_display_order_ids': jsonEncode(order),
        },
        'diting_express_prefs': const {},
        'diting_settings': const {'app_work_mode': 'normal'},
      });

  List<String> persistedOrder(MemoryLegacyPrefsStore store) => (jsonDecode(
    store.read('dns_vpn_prefs', 'provider_display_order_ids')! as String,
  ) as List).cast<String>();

  test('同组换位只动本组的槽位', () {
    final next = reorderProviderIds(
      order: const [
        'preset_alidns_dns',
        'preset_dnspod_doh',
        'preset_dnspod_dns',
        'preset_alidns_doh',
      ],
      groupIds: const ['preset_dnspod_doh', 'preset_alidns_doh'],
      oldIndex: 1,
      newIndex: 0,
    );

    expect(next, const [
      'preset_alidns_dns',
      'preset_alidns_doh',
      'preset_dnspod_dns',
      'preset_dnspod_doh',
    ]);
  });

  test('未排序的服务商排在已排序的后面，并保持目录顺序', () {
    final catalog = [
      for (final id in const ['a', 'b', 'c']) _providerOf(id),
    ];
    final ordered = orderedProviders(catalog, const ['c']);

    expect(
      [for (final provider in ordered) provider.id],
      const ['c', 'a', 'b'],
    );
  });

  test('首页服务列表按保存的顺序排列', () {
    final container = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(
          store(
            order: const [
              'preset_google_doh',
              'preset_alidns_doh',
              'preset_dnspod_doh',
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(visibleProvidersProvider).first.id,
      'preset_google_doh',
    );
  });

  testWidgets('拖动行后写回顺序', (tester) async {
    final prefs = store();
    // Tall enough for the whole page: an off-screen row cannot receive the drag.
    tester.view.physicalSize = const Size(1170, 5600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [legacyPrefsStoreProvider.overrideWithValue(prefs)],
        child: const AppHost(child: ProviderVisibilityPage()),
      ),
    );
    await tester.pumpAndSettle();

    // `ReorderableListView`s follow the page sections: DNS, DoH, DoT.
    Finder dohList() => find.byType(ReorderableListView).at(1);
    Finder rowText(String name) =>
        find.descendant(of: dohList(), matching: find.text(name));
    double topOf(String name) => tester.getTopLeft(rowText(name)).dy;
    expect(topOf('阿里云'), lessThan(topOf('Google')));

    // The DoH rows use the handle to move; the row itself only toggles, so the drag starts
    // immediately on the handle.
    final handle = find.descendant(
      of: find.descendant(of: dohList(), matching: find.byType(ListItem)).last,
      matching: find.byWidgetPredicate(
        (widget) => widget is GlyphIcon && widget.glyph == AppGlyphs.dragHandle,
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var step = 0; step < 12; step++) {
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(topOf('Google'), lessThan(topOf('阿里云')));
    final order = persistedOrder(prefs);
    expect(
      order.indexOf('preset_google_doh'),
      lessThan(order.indexOf('preset_alidns_doh')),
    );
  });
}

MockProvider _providerOf(String id) => MockProvider(
  id: id,
  name: id,
  protocol: ProviderProtocol.dns,
  address: '1.1.1.1:53',
  latencyMs: -1,
);

/// Custom providers are the ones the user maintains, so they sit above the built-in presets.
void _management() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('自定义服务商排在内置服务商上方', (tester) async {
    final store = MemoryLegacyPrefsStore({
      'dns_vpn_prefs': {
        'user_providers_json': jsonEncode([
          {
            'id': 'user_1',
            'name': '自建 DoH',
            'protocol': 'DOH',
            'url': 'https://dns.example.com/dns-query',
            'host': '',
            'port': 443,
          },
        ]),
        'preset_dns_service': 'DOH',
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

    expect(
      tester.getTopLeft(find.text('自定义服务商')).dy,
      lessThan(tester.getTopLeft(find.text('内置服务商')).dy),
    );
  });
}
