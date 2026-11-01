// Desktop home dashboard (docs/development/flutter-desktop-ui.md step 3): the Android skeleton —
// power button, sentence, card board — over the same stored layout, with honest "not connected"
// bodies until the local HTTP API lands in step 4.

import 'dart:convert';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/dashboard_models.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/pages/home/desktop_home_page.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/widgets/home_power_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    Map<String, Map<String, Object?>>? seed,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore(seed),
          ),
        ],
        child: const DesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopHomePage)).l10n;

  testWidgets('首页是安卓仪表盘骨架：电源按钮 + 诗句 + 卡片板', (tester) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopHomePage), findsOneWidget);
    expect(find.byType(HomePowerButton), findsOneWidget);
    // The sentence under the button is the stored one, defaulted from the ARB.
    expect(find.text(l10n.taglineStopped), findsOneWidget);
    // No fake figures: every card states that it is not connected yet.
    expect(
      find.descendant(
        of: find.byType(DesktopHomeBoard),
        matching: find.byType(DashboardChip),
      ),
      findsNWidgets(defaultDashboardWidgets.length),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('卡片板沿用安卓默认顺序', (tester) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);

    final titles = [
      for (final header in tester.widgetList<DashboardCardHeader>(
        find.byType(DashboardCardHeader),
      ))
        header.title,
    ];
    expect(titles, [
      for (final widget in defaultDashboardWidgets) widget.label(l10n),
    ]);
    expect(
      find.byType(DashboardCard),
      findsNWidgets(defaultDashboardWidgets.length),
    );
  });

  testWidgets('卡片板读同一份已保存布局', (tester) async {
    // Reversed and shortened: the desktop board must follow the user's own order, not the defaults.
    await pumpHome(
      tester,
      seed: {
        'dns_vpn_prefs': {
          'dashboard_widget_order': jsonEncode(['intranetIp', 'status']),
          'dashboard_widget_layout_version': 1,
        },
      },
    );
    final l10n = l10nOf(tester);
    final titles = [
      for (final header in tester.widgetList<DashboardCardHeader>(
        find.byType(DashboardCardHeader),
      ))
        header.title,
    ];
    expect(titles, [l10n.intranetIpTitle, l10n.statusTitle]);
  });

  testWidgets('清空后的卡片板是空状态而不是恢复默认', (tester) async {
    await pumpHome(
      tester,
      seed: {
        'dns_vpn_prefs': {
          'dashboard_widget_order': '[]',
          'dashboard_widget_layout_version': 1,
        },
      },
    );
    final l10n = l10nOf(tester);
    expect(find.byType(DashboardCard), findsNothing);
    expect(find.text(l10n.dashboardEmptyLabel), findsOneWidget);
  });

  testWidgets('电源按钮尚未接入时说明原因，而不是假装启动', (tester) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.byType(HomePowerButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.homePowerPending), findsOneWidget);
    expect(l10n.homePowerPending, isNotEmpty);
  });

  testWidgets('电源按钮的语义标签不被诗句污染', (tester) async {
    // Sharing the header must not fold the sentence into the button's label: a screen reader would
    // read the whole poem as the button name.
    final handle = tester.ensureSemantics();
    await pumpHome(tester);
    final l10n = l10nOf(tester);

    final node = tester.getSemantics(find.byType(HomePowerButton));
    expect(node.label, l10n.powerButtonStart);
    expect(find.bySemanticsLabel(l10n.powerButtonStart), findsOneWidget);
    // Verification runs after tear-downs, so the handle must go here.
    handle.dispose();
  });

  testWidgets('首页在窄窗口下无溢出', (tester) async {
    await pumpHome(tester, size: const Size(390, 844));
    expect(find.byType(DesktopHomeBoard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页在 1.4 倍字号下无溢出', (tester) async {
    await pumpHome(
      tester,
      seed: {
        'dns_vpn_prefs': {'app_text_scale': 1.4},
      },
    );
    expect(tester.takeException(), isNull);
  });
}
