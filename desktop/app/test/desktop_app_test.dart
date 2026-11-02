import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/app/theme/manager.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/home/desktop_home_page.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop entry uses Android theme and scopes', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(
            FakeDesktopBackend().client(),
          ),
        ],
        child: const DesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(DesktopHomePage));
    final expected = buildAppTheme(
      AppThemeSpec(
        seedColor: AppPalette.blue.effectiveSeed,
        brightness: Brightness.light,
      ),
    );
    final actual = Theme.of(context);
    expect(actual.colorScheme, expected.colorScheme);
    expect(
      actual.textTheme.bodyLarge?.fontSize,
      expected.textTheme.bodyLarge?.fontSize,
    );
    expect(
      actual.textTheme.bodyLarge?.height,
      expected.textTheme.bodyLarge?.height,
    );
    expect(
      actual.textTheme.bodyLarge?.fontWeight,
      expected.textTheme.bodyLarge?.fontWeight,
    );
    expect(
      actual.textTheme.labelSmall?.fontSize,
      expected.textTheme.labelSmall?.fontSize,
    );
    expect(actual.cardTheme.shape, expected.cardTheme.shape);
    expect(actual.pageTransitionsTheme, expected.pageTransitionsTheme);
    expect(ViewScope.isMobileOf(context), isFalse);
    expect(MeasureScope.of(context), isNotNull);
    expect(UiLocalizations.of(context), isNotNull);
    expect(find.byType(CommonScaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance changes reuse Android providers and text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryLegacyPrefsStore({
      LegacySettings.uiContainer: {'app_text_scale': 1.2},
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(
            FakeDesktopBackend().client(),
          ),
        ],
        child: const DesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopApp)),
    );
    container.read(themeModeProvider.notifier).select(AppThemeMode.dark);
    container.read(pureBlackProvider.notifier).toggle(true);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(DesktopHomePage));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).colorScheme.surface, Colors.black);
    expect(ViewScope.isMobileOf(context), isTrue);
    expect(MediaQuery.textScalerOf(context).scale(1), 1.2);
    expect(store.read(LegacySettings.uiContainer, 'pure_black_theme'), true);
  });

  testWidgets('desktop keeps the system font over a stored custom family', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryLegacyPrefsStore({
      LegacySettings.uiContainer: {
        'app_font_family': 'CustomFace',
        'app_imported_fonts': '[{"family":"CustomFace","label":"CustomFace","path":"C:/tmp/custom.ttf"}]',
      },
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(
            FakeDesktopBackend().client(),
          ),
        ],
        child: const DesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(DesktopHomePage)));
    final system = Typography.material2021(platform: defaultTargetPlatform);
    expect(theme.textTheme.bodyLarge?.fontFamily, isNot('CustomFace'));
    expect(
      theme.textTheme.bodyLarge?.fontFamily,
      system.black.bodyLarge?.fontFamily,
    );
    // The Han fallback chain is also a customisation; the desktop drops it too.
    expect(
      theme.textTheme.bodyLarge?.fontFamilyFallback,
      system.black.bodyLarge?.fontFamilyFallback,
    );
  });
}
