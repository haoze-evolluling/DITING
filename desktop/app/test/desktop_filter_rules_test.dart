// Desktop hub custom rules (desktop parity): the AdGuard syntax
// guide beside the editor that replaces the whole rule list. The text is a local draft; only the
// save button posts it, and the page then adopts the list the service re-reads.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_rules_page.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_custom_rules_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpRules(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) async {
    final fake = backend ?? FakeDesktopBackend();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: const DesktopApp(initialLocation: DesktopFilterRulesPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopFilterRulesPage)).l10n;

  Finder inEditor(Finder matching) => find.descendant(
    of: find.byType(CustomRulesEditorCard),
    matching: matching,
  );

  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(
      tester.element(finder),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  test('文本按行拆分，去掉空白行与首尾空格', () {
    expect(desktopCustomRuleLines(''), isEmpty);
    expect(
      desktopCustomRuleLines(' ||ads.example^ \n\n! comment\n@@||safe^ \n'),
      ['||ads.example^', '! comment', '@@||safe^'],
    );
  });

  testWidgets('编辑器显示服务返回的规则与语法指南', (tester) async {
    await pumpRules(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopFilterGuideTitle), findsOneWidget);
    final field = tester.widget<TextField>(inEditor(find.byType(TextField)));
    expect(field.controller?.text, '||ads.example^\n@@||safe.example^');
    expect(
      find.text(l10n.desktopFilterRulesLineCount(2)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存提交去空行后的整份规则并回显服务端值', (tester) async {
    final backend = await pumpRules(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(
      inEditor(find.byType(TextField)),
      ' ||new.example^ \n\n@@||allow.example^\n',
    );
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.desktopFilterRulesLineCount(2)),
      findsOneWidget,
    );

    await tapAt(tester, find.text(l10n.desktopFilterRulesSave));

    expect(backend.customRuleUpdates.single, [
      '||new.example^',
      '@@||allow.example^',
    ]);
    final field = tester.widget<TextField>(inEditor(find.byType(TextField)));
    expect(field.controller?.text, '||new.example^\n@@||allow.example^');
    expect(find.text(l10n.desktopFilterRulesSaved), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存被拒时说明原因并保留草稿', (tester) async {
    final backend = await pumpRules(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tester.enterText(inEditor(find.byType(TextField)), '||keep.example^');
    await tapAt(tester, find.text(l10n.desktopFilterRulesSave));

    expect(
      find.text(l10n.desktopFilterRulesSaveFailed('write rejected')),
      findsWidgets,
    );
    final field = tester.widget<TextField>(inEditor(find.byType(TextField)));
    expect(field.controller?.text, '||keep.example^');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗下指南与编辑器单列排列且不横向溢出', (tester) async {
    await pumpRules(tester, size: const Size(390, 844));
    expect(find.byType(CustomRulesEditorCard), findsOneWidget);
    expect(find.byType(RuleSyntaxGuideCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
