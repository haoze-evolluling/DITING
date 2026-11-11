/// What the appearance page renders: the mode resolved against the platform, and the scheme the
/// previews are painted with.
///
/// Both panes of the page ask the same question — "which scheme is on screen right now" — and a
/// palette tile that resolved the mode on its own would disagree with the preview beside it the
/// moment one of them was updated.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/widgets/appearance/theme_preview.dart';
import 'package:material_ui/material_ui.dart';

/// Light or dark as it is actually shown; `system` follows the platform.
Brightness appearanceBrightnessOf(BuildContext context, AppThemeMode mode) =>
    switch (mode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };

/// The scheme one palette resolves to. Shares [demoColorScheme]'s cache with the mobile pages, so
/// the previews cost a map lookup once the palette has been drawn.
ColorScheme appearanceColorScheme({
  required AppPalette palette,
  required Brightness brightness,
  required bool pureBlack,
}) => demoColorScheme(
  seed: palette.effectiveSeed,
  brightness: brightness,
  pureBlack: pureBlack,
);

/// The mode as the page should name it. "Follow the system" on its own leaves the reader guessing
/// whether they are looking at the light or the dark window, so the resolved side is spelled out.
String appearanceModeLabel(
  AppL10n l10n,
  AppThemeMode mode,
  Brightness brightness,
) => switch (mode) {
  AppThemeMode.system => l10n.desktopSettingsSystemResolved(
    (brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light)
        .label(l10n),
  ),
  _ => mode.label(l10n),
};
