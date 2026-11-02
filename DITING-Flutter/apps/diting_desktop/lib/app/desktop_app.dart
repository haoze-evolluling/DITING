import 'package:diting_shared/app/bootstrap.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/l10n/ui_strings.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/app/theme/manager.dart';
import 'package:diting_desktop/router.dart';
import 'package:diting_desktop/widgets/desktop_auth_gate.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Desktop app root: exactly the Android theme, localization and scope assembly, over the shared
/// six-branch shell ([createDesktopRouter]), without any Android startup work.
///
/// Keep this in step with `DitingApp`: cached light/dark themes, localized delegates,
/// `ThemeCrossFade`, system overlay, glass scopes, and [AppScopes] above the Navigator. Anything
/// that only exists because the host is Wails/WebView belongs in `apps/diting_desktop/lib/data`.
///
/// The same bundle is also served to browsers by the LAN web console, so [DesktopAuthGate] sits above
/// the router: it lets the desktop window through and asks a browser for the admin credential first.
class DesktopApp extends ConsumerStatefulWidget {
  const DesktopApp({super.key, this.initialLocation});

  /// Test-only: start at a route directly instead of navigating there.
  final String? initialLocation;

  @override
  ConsumerState<DesktopApp> createState() => _DesktopAppState();
}

class _DesktopAppState extends ConsumerState<DesktopApp> {
  final _themes = AppThemeCache();
  late final GoRouter _router = createDesktopRouter(
    initialLocation: widget.initialLocation ?? Routes.home,
  );

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final palette = ref.watch(paletteProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final textScale = ref.watch(textScaleProvider);
    final fontFamily = ref.watch(selectedFontFamilyProvider);
    final locale = ref.watch(appLocaleProvider);
    final background = ref.watch(customBackgroundProvider);
    final showBackground =
        background.enabled &&
        background.currentUri != null &&
        background.currentUri!.isNotEmpty;
    final pair = AppThemePair(
      seedColor: palette.effectiveSeed,
      pureBlack: pureBlack,
      transparentPage: showBackground,
      fontFamily: fontFamily,
    );

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      themeMode: switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      theme: _themes.of(pair.lightSpec, locales: AppL10n.supportedLocales),
      darkTheme: _themes.of(pair.darkSpec, locales: AppL10n.supportedLocales),
      localizationsDelegates: const [
        AppUiLocalizations.delegate,
        AppL10n.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppL10n.supportedLocales,
      locale: locale,
      builder: (context, child) {
        setCurrentL10n(AppL10n.of(context));
        final glass = ref.watch(liquidGlassModeProvider);
        return ThemeCrossFade(
          child: AppSystemUi(
            child: AppScopes(
              textScale: textScale,
              child: LiquidGlassScope(
                enabled: glass.enabled,
                quality: glass.quality,
                child: LiquidGlassHost(
                  enabled: glass.enabled,
                  // The web console gates on a session; the desktop window passes straight through.
                  child: DesktopAuthGate(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
