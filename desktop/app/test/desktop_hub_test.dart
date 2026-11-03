// Desktop hub information architecture (desktop parity): the six
// use-order categories, which entries each one owns, and the two operation cards that belong to
// the diagnosis category instead of floating loose on the board.
//
// The point of these cases is placement, not page content: the sub-pages have their own suites, so
// here a category only has to prove which rows and cards it holds.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting_desktop/pages/settings/desktop_lan_web_page.dart';
import 'package:diting_desktop/pages/tools/widgets/emergency_restore_card.dart';
import 'package:diting_desktop/pages/tools/widgets/port_diagnosis_card.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_page_harness.dart';

void main() {
  Future<void> pumpHub(WidgetTester tester) =>
      pumpDesktopPage(tester, path: Routes.hub);

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopFeatureHubPage)).l10n;

  /// The category column that owns [title]: its nearest [Column] ancestor is the one `_category`
  /// builds, so descendants of it are exactly that category's rows and cards.
  Finder categoryOf(String title) => find
      .ancestor(of: find.text(title), matching: find.byType(Column))
      .first;

  testWidgets('功能中心分成六个按使用顺序排列的分类', (tester) async {
    await pumpHub(tester);
    final l10n = l10nOf(tester);

    for (final title in [
      l10n.desktopHubResolveSection,
      l10n.desktopHubProtectSection,
      l10n.desktopHubPrivacySection,
      l10n.desktopHubShareSection,
      l10n.desktopHubDiagnoseSection,
      l10n.desktopHubAppSection,
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺少分类「$title」');
    }
    // 旧的四个分类名不再出现：设置与网络被拆开，工具箱不再是标题。
    for (final gone in const ['设备与网络', '设置', '检测工具']) {
      expect(find.text(gone), findsNothing);
    }
  });

  testWidgets('每个二级界面只出现在一个分类下', (tester) async {
    await pumpHub(tester);
    final l10n = l10nOf(tester);

    final expected = <String, List<String>>{
      l10n.desktopHubResolveSection: [
        l10n.desktopHubUpstream,
        l10n.desktopHubCache,
        l10n.desktopHubRewrite,
        l10n.desktopHubDns64,
      ],
      l10n.desktopHubProtectSection: [
        l10n.desktopHubFilterServices,
        l10n.desktopHubFilterLists,
        l10n.desktopHubFilterRules,
        l10n.desktopHubFilterConfig,
        l10n.desktopHubFilterSchedule,
      ],
      l10n.desktopHubPrivacySection: [
        l10n.desktopHubPrivacy,
        l10n.desktopHubEncrypted,
      ],
      l10n.desktopHubShareSection: [
        l10n.desktopHubAdapters,
        l10n.desktopHubLanDns,
        l10n.desktopLanWebPageTitle,
        l10n.desktopHubClientAccess,
      ],
      l10n.desktopHubDiagnoseSection: [
        l10n.desktopToolsRulePageTitle,
        l10n.desktopHubQueryLog,
      ],
      l10n.desktopHubAppSection: [
        l10n.desktopSettingsAppearance,
        l10n.desktopServicePageTitle,
      ],
    };

    for (final entry in expected.entries) {
      final category = categoryOf(entry.key);
      for (final title in entry.value) {
        expect(
          find.descendant(of: category, matching: find.text(title)),
          findsOneWidget,
          reason: '「${entry.key}」应包含「$title」',
        );
        // 同一个入口不会在另一个分类里重复出现。
        expect(
          find.text(title),
          findsOneWidget,
          reason: '「$title」只应有一个入口',
        );
      }
      // 行数与预期一致，避免多出的入口挂在错误的分类上。
      expect(
        find.descendant(of: category, matching: find.byType(ListItem)),
        findsNWidgets(entry.value.length),
      );
    }
  });

  testWidgets('诊断与恢复分类里放着规则检测与两张操作卡', (tester) async {
    await pumpHub(tester);
    final l10n = l10nOf(tester);

    final category = categoryOf(l10n.desktopHubDiagnoseSection);
    expect(
      find.descendant(of: category, matching: find.byType(PortDiagnosisCard)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: category,
        matching: find.byType(EmergencyRestoreCard),
      ),
      findsOneWidget,
    );
    // 两张卡不再是游离卡片：它们只出现在这一个分类里。
    expect(find.byType(PortDiagnosisCard), findsOneWidget);
    expect(find.byType(EmergencyRestoreCard), findsOneWidget);
  });

  testWidgets('网络共享分类的局域网控制台入口仍能打开子页', (tester) async {
    await pumpHub(tester);
    final l10n = l10nOf(tester);

    final entry = find.descendant(
      of: categoryOf(l10n.desktopHubShareSection),
      matching: find.text(l10n.desktopLanWebPageTitle),
    );
    await Scrollable.ensureVisible(
      tester.element(entry),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(DesktopLanWebPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
