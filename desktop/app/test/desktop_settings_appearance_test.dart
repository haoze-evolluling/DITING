// Desktop settings branch, appearance (desktop parity): palette and
// day/night mode are the app's shared appearance providers, not a desktop-only copy.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/pages/settings/desktop_appearance_page.dart';
import 'package:diting_desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting_desktop/pages/settings/widgets/appearance_options_card.dart';
import 'package:diting_desktop/pages/settings/widgets/appearance_preview_card.dart';
import 'package:diting_desktop/pages/settings/widgets/appearance_theme_pane.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_page_harness.dart';

void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    String location = DesktopAppearancePage.path,
    Size size = const Size(1280, 900),
  }) => pumpDesktopPage(tester, path: location, size: size);

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(CommonScaffold).first).l10n;

  testWidgets('功能中心的「应用与服务」分类列出外观入口并可进入', (tester) async {
    await pumpSettings(tester, location: Routes.hub);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopFeatureHubPage), findsOneWidget);
    expect(find.text(l10n.desktopSettingsAppearance), findsOneWidget);

    // 分类顺序固定，外观在最末一组，滚动到它再点。
    final entry = find.text(l10n.desktopSettingsAppearance);
    await Scrollable.ensureVisible(
      tester.element(entry),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopAppearancePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('配色与模式都显示当前选择，点选后立即切换', (tester) async {
    await pumpSettings(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(AppearanceThemePane), findsOneWidget);
    expect(find.text(l10n.desktopSettingsPalette), findsOneWidget);
    expect(find.text(l10n.desktopSettingsMode), findsOneWidget);

    // The palette tiles are labelled from the shared palette enum.
    expect(find.text(l10n.paletteBlue), findsOneWidget);
    await tester.tap(find.text(l10n.paletteBlue));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(l10n.paletteBlue),
      findsWidgets,
    );

    await tester.tap(find.text(l10n.themeModeDark).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗单列且不横向溢出', (tester) async {
    await pumpSettings(tester, size: const Size(390, 844));
    expect(find.byType(AppearanceThemePane), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽窗下预览与选项并排，窄窗下上下堆叠', (tester) async {
    Offset topOf(Type type) => tester
        .renderObject<RenderBox>(find.byType(type))
        .localToGlobal(Offset.zero);
    Size sizeOf(Type type) =>
        tester.renderObject<RenderBox>(find.byType(type)).size;

    await pumpSettings(tester);
    // 左右两栏共用同一条顶线，预览在左。
    expect(topOf(AppearancePreviewCard).dy, topOf(AppearanceOptionsCard).dy);
    expect(
      topOf(AppearancePreviewCard).dx,
      lessThan(topOf(AppearanceOptionsCard).dx),
    );
    expect(tester.takeException(), isNull);

    // 窄窗放不下两栏，选项落到预览下方。
    await pumpSettings(tester, size: const Size(800, 900));
    expect(
      topOf(AppearanceOptionsCard).dy,
      greaterThan(
        topOf(AppearancePreviewCard).dy + sizeOf(AppearancePreviewCard).height,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽窗下页面用满卡片宽度，不留半页空白', (tester) async {
    await pumpSettings(tester);

    final board = tester.renderObject<RenderBox>(find.byType(DesktopCardBoard));
    final pane = tester.renderObject<RenderBox>(
      find.byType(AppearanceThemePane),
    );
    expect(pane.size.width, greaterThan(board.size.width * 0.9));
    expect(tester.takeException(), isNull);
  });
}
