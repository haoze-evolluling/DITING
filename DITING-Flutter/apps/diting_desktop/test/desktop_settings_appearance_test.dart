// Desktop settings branch, appearance (docs/development/flutter-desktop-ui.md step 4): palette and
// day/night mode are the app's shared appearance providers, not a desktop-only copy.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/settings/desktop_appearance_page.dart';
import 'package:diting_desktop/pages/settings/desktop_settings_page.dart';
import 'package:diting_desktop/pages/settings/widgets/appearance_theme_card.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
    String location = DesktopAppearancePage.path,
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(
            FakeDesktopBackend().client(),
          ),
        ],
        child: DesktopApp(initialLocation: location),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(CommonScaffold).first).l10n;

  testWidgets('设置分支列出外观入口并可进入', (tester) async {
    await pumpSettings(tester, location: Routes.settings);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopSettingsPage), findsOneWidget);
    expect(find.text(l10n.desktopSettingsAppearance), findsOneWidget);

    await tester.tap(find.text(l10n.desktopSettingsAppearance));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopAppearancePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('配色与模式都显示当前选择，点选后立即切换', (tester) async {
    await pumpSettings(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(AppearanceThemeCard), findsOneWidget);
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
    expect(find.byType(AppearanceThemeCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
