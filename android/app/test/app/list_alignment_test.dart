import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/widgets/leading_slot.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_host.dart';
import '../support/fake_vpn_controller.dart';
import '../support/test_hooks.dart';

const _aboutRowTitles = <String>[
  '项目',
  '加入 QQ 群',
  '赞助',
  '赞助者名单',
  '关闭启动时检查更新',
  'blockads-android',
  '使用须知与免责声明',
];

void main() {
  installGlobalTestHooks();

  Map<String, double> leftEdges(WidgetTester tester, List<String> labels) => {
    for (final label in labels)
      if (find.text(label).evaluate().isNotEmpty)
        label: tester.getTopLeft(find.text(label).first).dx,
  };

  testWidgets('关于页所有行共享同一条文字列', (tester) async {
    tester.view.physicalSize = const Size(1170, 4600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final vpn = FakeVpnController()
      ..statusValue = const VpnStatus(running: false, persisted: false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          vpnControllerProvider.overrideWithValue(vpn),
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
        ],
        child: DitingApp(initialLocation: Routes.about),
      ),
    );
    await tester.pumpAndSettle();

    final edges = leftEdges(tester, _aboutRowTitles);
    expect(
      edges.keys,
      containsAll(_aboutRowTitles),
      reason: '关于页缺少行，测试没覆盖到该行',
    );
    expect(
      edges.values.toSet(),
      hasLength(1),
      reason: '关于页存在文字左边缘不一致的行：$edges',
    );
  });

  testWidgets('LeadingSlot 让不同宽度的前置图标落在同一列', (tester) async {
    await tester.pumpWidget(
      AppHost(
        child: Scaffold(
          body: ListView(
            children: [
              generateSection(
                items: [
                  ListItem(
                    leading: const LeadingSlot(
                      child: GlyphIcon(AppGlyphs.heart, size: 20),
                    ),
                    title: const Text('窄图标'),
                  ),
                  ListItem(
                    leading: LeadingSlot(
                      child: SizedBox.square(
                        dimension: 34,
                        child: const ColoredBox(color: Color(0x11000000)),
                      ),
                    ),
                    title: const Text('徽章'),
                  ),
                  ListItem(
                    leading: const LeadingSlot(
                      child: SizedBox.square(dimension: 40),
                    ),
                    title: const Text('应用图标'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final edges = leftEdges(tester, const ['窄图标', '徽章', '应用图标']);
    expect(edges, hasLength(3));
    expect(
      edges.values.toSet(),
      hasLength(1),
      reason: 'LeadingSlot 未能把不同宽度的前置图标对齐：$edges',
    );
  });
}
